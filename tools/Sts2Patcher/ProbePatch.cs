using Mono.Cecil;
using Mono.Cecil.Cil;

namespace Sts2Patcher;

/// <summary>
/// Testing aid: NGame._Ready starts with a call to Sts2Probe.Probe.Install() (tools/Sts2Probe), which logs slow
/// frames with their GC counts when a "perf_log" file sits next to the packs, and does nothing otherwise.
/// Only applied when the patcher is given the probe assembly; Sts2Probe.dll must then ship next to sts2.dll.
/// </summary>
public sealed class ProbePatch(string probeDll) : IPatch
{
    public string Name => "NGame._Ready: install the frame/GC probe (Sts2Probe)";

    public void Apply(ModuleDefinition module)
    {
        var nGame = module.GetType("MegaCrit.Sts2.Core.Nodes.NGame") ?? throw new PatchException("NGame not found");
        var ready = nGame.Methods.SingleOrDefault(m => m.Name == "_Ready" && m.Parameters.Count == 0 && m.HasBody)
            ?? throw new PatchException("NGame._Ready() not found");

        using var probe = AssemblyDefinition.ReadAssembly(probeDll);
        var install = probe.MainModule.GetType("Sts2Probe.Probe")?.Methods
            .SingleOrDefault(m => m.Name == "Install" && m.IsStatic && m.Parameters.Count == 0)
            ?? throw new PatchException($"Sts2Probe.Probe.Install() not found in {probeDll}");

        var il = ready.Body.GetILProcessor();
        il.InsertBefore(ready.Body.Instructions[0], il.Create(OpCodes.Call, module.ImportReference(install)));
    }
}
