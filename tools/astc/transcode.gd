extends SceneTree
## Converts the game's desktop GPU textures (BC1/BC3/BC7 .ctex) to ASTC 4x4 .ctex for phones.
## Run headless with the Godot editor binary (it has the BC decoder and the astcenc encoder):
##   Godot --headless --path tools/astc --script transcode.gd -- <in dir> <out dir>
## Every <in dir>/<name>.ctex without a matching <out dir>/<name>.ctex is converted. Writes into <out dir> only.
##
## Why not Image.compress() directly: Godot's ASTC encoder stretches images whose size isn't a multiple of 4,
## which would shift every sprite cut from an atlas. Here the image is padded (edge pixels repeated) to whole
## blocks, encoded, and stored with its original size; Godot stores block formats that way already (the
## game's own BC textures have odd sizes too), and only the visible area is ever sampled.

const GST2_HEADER := 36  # "GST2", version, width, height, flags, mipmap limit, 3 reserved (u32 each)
const DATA_FORMAT_IMAGE := 0
const BC_FORMATS := [Image.FORMAT_DXT1, Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_BPTC_RGBA]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -- <in dir> <out dir>")
		quit(2)
		return
	var in_dir: String = args[0]
	var out_dir: String = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var todo := []
	for name in DirAccess.get_files_at(in_dir):
		if name.ends_with(".ctex") and not FileAccess.file_exists(out_dir.path_join(name)):
			todo.append(name)
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for i in todo.size():
		var err := _convert(in_dir.path_join(todo[i]), out_dir.path_join(todo[i]))
		if err != "":
			printerr("FAILED %s: %s" % [todo[i], err])
			failed += 1
		if (i + 1) % 50 == 0:
			print("%d/%d converted (%ds)" % [i + 1, todo.size(), (Time.get_ticks_msec() - t0) / 1000])
	print("done: %d converted, %d failed, %ds" % [todo.size() - failed, failed, (Time.get_ticks_msec() - t0) / 1000])
	quit(1 if failed > 0 else 0)


## Returns "" on success, else the reason.
func _convert(src: String, dst: String) -> String:
	var b := FileAccess.get_file_as_bytes(src)
	if b.size() < GST2_HEADER + 16 or b.slice(0, 4).get_string_from_ascii() != "GST2":
		return "not a GST2 texture"
	var data_format := b.decode_u32(GST2_HEADER)
	var w := b.decode_u16(GST2_HEADER + 4)
	var h := b.decode_u16(GST2_HEADER + 6)
	var mipmaps := b.decode_u32(GST2_HEADER + 8)
	var format := b.decode_u32(GST2_HEADER + 12)
	if data_format != DATA_FORMAT_IMAGE or not format in BC_FORMATS:
		return "not a BC image (data format %d, image format %d)" % [data_format, format]
	if mipmaps != 0:
		return "has mipmaps (not handled)"
	var img := Image.create_from_data(w, h, false, format, b.slice(GST2_HEADER + 16))
	if img.is_empty():
		return "could not read the image data"
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	var pw := (w + 3) / 4 * 4
	var ph := (h + 3) / 4 * 4
	var padded := img
	if pw != w or ph != h:
		padded = Image.create_empty(pw, ph, false, Image.FORMAT_RGBA8)
		padded.blit_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
		for x in range(w, pw):
			padded.blit_rect(img, Rect2i(w - 1, 0, 1, h), Vector2i(x, 0))
		for y in range(h, ph):
			padded.blit_rect(padded, Rect2i(0, h - 1, pw, 1), Vector2i(0, y))
	if padded.compress(Image.COMPRESS_ASTC, Image.COMPRESS_SOURCE_GENERIC, Image.ASTC_FORMAT_4x4) != OK:
		return "ASTC encode failed"
	var astc := padded.get_data()
	if astc.size() != (pw / 4) * (ph / 4) * 16:
		return "unexpected ASTC size %d" % astc.size()

	# Same file header (texture size and flags unchanged), then the image block in ASTC.
	var out := b.slice(0, GST2_HEADER)
	var block := PackedByteArray()
	block.resize(16)
	block.encode_u32(0, DATA_FORMAT_IMAGE)
	block.encode_u16(4, w)
	block.encode_u16(6, h)
	block.encode_u32(8, 0)
	block.encode_u32(12, Image.FORMAT_ASTC_4x4)
	out.append_array(block)
	out.append_array(astc)
	var tmp := dst + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "cannot write %s" % tmp
	f.store_buffer(out)
	f.close()
	if DirAccess.rename_absolute(tmp, dst) != OK:
		return "cannot rename to %s" % dst
	return ""
