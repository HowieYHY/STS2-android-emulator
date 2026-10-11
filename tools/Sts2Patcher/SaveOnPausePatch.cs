using Mono.Cecil;
using Mono.Cecil.Cil;

namespace Sts2Patcher;

/// <summary>
/// The game writes settings/prefs/progress/profile in NGame.Quit(), which runs on the window close request
/// (NOTIFICATION_WM_CLOSE_REQUEST, 1006). Android apps are almost never closed that way: they go to the
/// background and the system kills them later, so anything kept only in memory is lost (seen: the Early Access
/// disclaimer's "seen" flag, and settings changes).
///
/// Fix: NGame._Notification also flushes the same saves on NOTIFICATION_APPLICATION_PAUSED (2015), which Godot
/// sends on Android when the app leaves the foreground. It reuses the exact calls Quit() makes and does not quit.
/// </summary>
public sealed class SaveOnPausePatch : IPatch
{
    public string Name => "NGame: flush saves when Android pauses the app";

    private const int NotificationApplicationPaused = 2015; // Node.NOTIFICATION_APPLICATION_PAUSED (Godot 4.5 node.h)
    private const int NotificationWmCloseRequest = 1006;
    private const string HelperName = "__sts2port_FlushSaves";

    public void Apply(ModuleDefinition module)
    {
        var nGame = module.GetType("MegaCrit.Sts2.Core.Nodes.NGame") ?? throw new PatchException("NGame not found");
        var notification = nGame.Methods.SingleOrDefault(m => m.Name == "_Notification" && m.Parameters.Count == 1)
            ?? throw new PatchException("NGame._Notification(int) not found");
        var quit = nGame.Methods.SingleOrDefault(m => m.Name == "Quit" && m.Parameters.Count == 0)
            ?? throw new PatchException("NGame.Quit() not found");

        // Sanity check: _Notification still means "if (what == 1006) Quit();".
        var ins = notification.Body.Instructions;
        if (!ins.Any(i => i.OpCode == OpCodes.Ldc_I4 && (int)i.Operand == NotificationWmCloseRequest)
            || !ins.Any(i => i.OpCode == OpCodes.Call && i.Operand is MethodReference m && m.Name == "Quit"))
            throw new PatchException("_Notification no longer handles 1006 -> Quit()");

        // Take the save calls straight from Quit(): SaveManager.get_Instance, SaveSettings, get_IsProfileInitialized,
        // SavePrefsFile, SaveProgressFile, SaveProfile.
        var calls = quit.Body.Instructions
            .Where(i => (i.OpCode == OpCodes.Call || i.OpCode == OpCodes.Callvirt) && i.Operand is MethodReference)
            .Select(i => (MethodReference)i.Operand)
            .Where(m => m.DeclaringType.FullName == "MegaCrit.Sts2.Core.Saves.SaveManager")
            .ToList();
        MethodReference Find(string name) => calls.FirstOrDefault(m => m.Name == name)
            ?? throw new PatchException($"Quit() no longer calls SaveManager.{name}");
        var getInstance = Find("get_Instance");
        var saveSettings = Find("SaveSettings");
        var isProfileInitialized = Find("get_IsProfileInitialized");
        var savePrefs = Find("SavePrefsFile");
        var saveProgress = Find("SaveProgressFile");
        var saveProfile = Find("SaveProfile");

        // private static void __sts2port_FlushSaves() — same order and guard as Quit().
        var helper = new MethodDefinition(HelperName,
            MethodAttributes.Private | MethodAttributes.Static | MethodAttributes.HideBySig, module.TypeSystem.Void);
        var il = helper.Body.GetILProcessor();
        var end = Instruction.Create(OpCodes.Ret);
        il.Emit(OpCodes.Call, getInstance);
        il.Emit(OpCodes.Callvirt, saveSettings);
        il.Emit(OpCodes.Call, getInstance);
        il.Emit(OpCodes.Callvirt, isProfileInitialized);
        il.Emit(OpCodes.Brfalse, end);
        il.Emit(OpCodes.Call, getInstance);
        il.Emit(OpCodes.Callvirt, savePrefs);
        il.Emit(OpCodes.Call, getInstance);
        il.Emit(OpCodes.Callvirt, saveProgress);
        il.Emit(OpCodes.Call, getInstance);
        il.Emit(OpCodes.Callvirt, saveProfile);
        il.Append(end);
        nGame.Methods.Add(helper);

        // Prepend to _Notification: if (what == 1015) __sts2port_FlushSaves();
        var p = notification.Body.GetILProcessor();
        var first = notification.Body.Instructions[0];
        p.InsertBefore(first, Instruction.Create(OpCodes.Ldarg_1));
        p.InsertBefore(first, Instruction.Create(OpCodes.Ldc_I4, NotificationApplicationPaused));
        p.InsertBefore(first, Instruction.Create(OpCodes.Bne_Un, first));
        p.InsertBefore(first, Instruction.Create(OpCodes.Call, helper));
    }
}
