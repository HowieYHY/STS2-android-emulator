using Mono.Cecil;
using Mono.Cecil.Cil;

namespace Sts2Patcher;

/// <summary>
/// Settings → "Skip Intro Logo" always showed ticked: NIntroLogoTickbox._Ready never calls SetFromSettings(), unlike
/// the game's other settings tickboxes (NFastModeTickbox etc.), so it shows the scene's default instead of the saved
/// value. With the setting off (the default) the ~9.6 s logo played on every launch while the box claimed it was
/// skipped. Fix: _Ready also calls SetFromSettings(), so the box tells the truth; the setting itself is untouched.
/// </summary>
public sealed class IntroLogoTickboxPatch : IPatch
{
    public string Name => "Settings: Skip Intro Logo tickbox shows the saved value";

    public void Apply(ModuleDefinition module)
    {
        var type = module.GetType("MegaCrit.Sts2.Core.Nodes.Screens.Settings.NIntroLogoTickbox")
            ?? throw new PatchException("NIntroLogoTickbox not found");
        var ready = type.Methods.SingleOrDefault(m => m.Name == "_Ready" && m.Parameters.Count == 0 && m.HasBody)
            ?? throw new PatchException("NIntroLogoTickbox._Ready() not found");
        var setFromSettings = type.Methods.SingleOrDefault(m => m.Name == "SetFromSettings" && m.Parameters.Count == 0)
            ?? throw new PatchException("NIntroLogoTickbox.SetFromSettings() not found");

        var ins = ready.Body.Instructions;
        if (ins.Any(i => i.Operand is MethodReference m && m.Name == "SetFromSettings"))
            throw new PatchException("_Ready already calls SetFromSettings (the game fixed it; drop this patch)");
        var rets = ins.Where(i => i.OpCode == OpCodes.Ret).ToList();
        if (rets.Count != 1 || rets[0] != ins[^1])
            throw new PatchException("_Ready no longer has a single return at the end");

        // Insert "this.SetFromSettings();" before the final return.
        var il = ready.Body.GetILProcessor();
        var ret = rets[0];
        var first = il.Create(OpCodes.Ldarg_0);
        il.InsertBefore(ret, first);
        il.InsertBefore(ret, il.Create(OpCodes.Call, setFromSettings));
        // Branches that targeted the return must now run the call too.
        foreach (var i in ins)
            if (i.Operand == ret && i != first) i.Operand = first;
    }
}
