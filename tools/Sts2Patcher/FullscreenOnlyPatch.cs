using Mono.Cecil;
using Mono.Cecil.Cil;

namespace Sts2Patcher;

/// <summary>
/// The port runs on the game's Null platform, which reports SupportedWindowMode.Any, so Settings offers a
/// Fullscreen tickbox. On Android, unticking it shrinks the game into a window under the system bars and touch no
/// longer lines up with what's drawn (taps hit the wrong control, so it can't even be ticked again).
///
/// Fix: NullPlatformUtilStrategy.GetSupportedWindowMode() returns FullscreenOnly, the game's own console-style mode:
/// it forces fullscreen even if settings.save says windowed (settings.save unchanged) and shows the tickbox disabled.
/// </summary>
public sealed class FullscreenOnlyPatch : IPatch
{
    public string Name => "Null platform: fullscreen only (no windowed mode on a phone)";

    private const string ModeType = "MegaCrit.Sts2.Core.Platform.SupportedWindowMode";

    public void Apply(ModuleDefinition module)
    {
        var strategy = module.GetType("MegaCrit.Sts2.Core.Platform.Null.NullPlatformUtilStrategy")
            ?? throw new PatchException("NullPlatformUtilStrategy not found");
        var method = strategy.Methods.SingleOrDefault(m => m.Name == "GetSupportedWindowMode" && m.Parameters.Count == 0)
            ?? throw new PatchException("NullPlatformUtilStrategy.GetSupportedWindowMode() not found");
        if (method.ReturnType.FullName != ModeType)
            throw new PatchException($"GetSupportedWindowMode() returns {method.ReturnType.FullName}, expected {ModeType}");

        var mode = module.GetType(ModeType) ?? throw new PatchException($"{ModeType} not found");
        int Value(string name) => (int)(mode.Fields.SingleOrDefault(f => f.Name == name && f.HasConstant)?.Constant
            ?? throw new PatchException($"{ModeType}.{name} not found"));
        int any = Value("Any"), fullscreenOnly = Value("FullscreenOnly");

        // Shape check: the body is still just "return SupportedWindowMode.Any;".
        var real = method.Body.Instructions.Where(i => i.OpCode != OpCodes.Nop).ToList();
        if (real.Count != 2 || real[1].OpCode != OpCodes.Ret || LoadedConstant(real[0]) != any)
            throw new PatchException("GetSupportedWindowMode() is no longer 'return SupportedWindowMode.Any;'");

        method.Body.Instructions.Clear();
        method.Body.Variables.Clear();
        method.Body.ExceptionHandlers.Clear();
        var il = method.Body.GetILProcessor();
        il.Emit(OpCodes.Ldc_I4, fullscreenOnly);
        il.Emit(OpCodes.Ret);
    }

    private static int? LoadedConstant(Instruction i) => i.OpCode.Code switch
    {
        Code.Ldc_I4_0 => 0, Code.Ldc_I4_1 => 1, Code.Ldc_I4_2 => 2, Code.Ldc_I4_3 => 3,
        Code.Ldc_I4_S => (sbyte)i.Operand, Code.Ldc_I4 => (int)i.Operand,
        _ => null,
    };
}
