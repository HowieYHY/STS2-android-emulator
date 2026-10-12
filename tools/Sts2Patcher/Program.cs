using Mono.Cecil;

namespace Sts2Patcher;

/// <summary>
/// Usage: Sts2Patcher &lt;input sts2.dll&gt; &lt;game data dir (for references)&gt; &lt;output sts2.dll&gt; [Sts2Probe.dll]
/// Applies every patch in <see cref="Patches.All"/>. Each patch checks the shape of the code it changes and
/// fails loudly if a game update changed it, rather than patching something it doesn't understand.
/// </summary>
public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length is not (3 or 4))
        {
            Console.Error.WriteLine("Usage: Sts2Patcher <input sts2.dll> <game data dir> <output sts2.dll> [Sts2Probe.dll]");
            return 2;
        }
        string input = Path.GetFullPath(args[0]), dataDir = Path.GetFullPath(args[1]), output = Path.GetFullPath(args[2]);
        if (string.Equals(input, output, StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine("Refusing to overwrite the input: the game folder must stay untouched.");
            return 2;
        }

        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(dataDir);
        // Read fully into memory so the input file is not kept open or touched.
        using var assembly = AssemblyDefinition.ReadAssembly(input, new ReaderParameters { AssemblyResolver = resolver, InMemory = true });
        var patches = args.Length == 4 ? [.. Patches.All, new ProbePatch(Path.GetFullPath(args[3]))] : Patches.All;
        foreach (var patch in patches)
        {
            try
            {
                patch.Apply(assembly.MainModule);
                Console.WriteLine($"patched: {patch.Name}");
            }
            catch (PatchException e)
            {
                Console.Error.WriteLine($"FAILED: {patch.Name}: {e.Message}");
                return 1;
            }
        }
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        assembly.Write(output);
        return 0;
    }
}

public sealed class PatchException(string message) : Exception(message);

public interface IPatch
{
    string Name { get; }
    void Apply(ModuleDefinition module);
}

public static class Patches
{
    public static readonly IPatch[] All = [new ModelDbLazyInitPatch(), new SaveOnPausePatch(), new FullscreenOnlyPatch(), new IntroLogoTickboxPatch()];
}
