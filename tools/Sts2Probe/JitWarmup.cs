using System;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Threading;
using Godot;

namespace Sts2Probe;

/// <summary>
/// Experiment: Mono on Android JIT-compiles each of the game's C# methods the first time it runs, which showed up as
/// 30-55 ms of compiling inside the first frames of every new card effect (measured with JitInfo). This compiles
/// sts2.dll's methods ahead of use on a low-priority background thread (by asking for each method's entry point), starting a
/// while after startup so it never competes with loading. Enabled by a "jit_warmup" file next to the packs.
/// </summary>
public static class JitWarmup
{
    private const int StartDelayMs = 20_000;
    private static readonly BindingFlags All =
        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly;

    public static void Start()
    {
        var thread = new Thread(Run) { IsBackground = true, Priority = ThreadPriority.Lowest, Name = "sts2port JIT warmup" };
        thread.Start();
    }

    private static void Run()
    {
        try
        {
            Thread.Sleep(StartDelayMs);
            var game = AppDomain.CurrentDomain.GetAssemblies().FirstOrDefault(a => a.GetName().Name == "sts2");
            if (game == null)
            {
                GD.PrintErr("[sts2probe] warmup: sts2 assembly not loaded");
                return;
            }
            var clock = Stopwatch.StartNew();
            long jit0 = System.Runtime.JitInfo.GetCompiledMethodCount(false);
            double jitMs0 = System.Runtime.JitInfo.GetCompilationTime(false).TotalMilliseconds;
            int done = 0, failed = 0;
            Type[] types;
            try { types = game.GetTypes(); }
            catch (ReflectionTypeLoadException e) { types = e.Types.Where(t => t != null).ToArray()!; }
            // Game logic first (cards, powers, monsters, commands), then the node/UI layer, then the rest.
            var ordered = types.OrderBy(t => t.Namespace?.StartsWith("MegaCrit.Sts2.Core.Models") == true ? 0
                : t.Namespace?.StartsWith("MegaCrit.Sts2.Core.Nodes") == true ? 1 : 2);
            foreach (var type in ordered)
            {
                if (type.ContainsGenericParameters)
                    continue;
                foreach (var method in type.GetMethods(All).Cast<MethodBase>().Concat(type.GetConstructors(All)))
                {
                    if (method.IsAbstract || method.ContainsGenericParameters || method.IsStatic && method.IsConstructor
                        || (method.MethodImplementationFlags & MethodImplAttributes.InternalCall) != 0)
                        continue;
                    try
                    {
                        // Mono's PrepareMethod doesn't compile (measured: no JIT activity); asking for the native
                        // entry point does.
                        method.MethodHandle.GetFunctionPointer();
                        if (++done % 5000 == 0)
                            GD.Print($"[sts2probe] warmup: {done} methods, {clock.ElapsedMilliseconds} ms");
                    }
                    catch (Exception e)
                    {
                        if (++failed <= 5)
                            GD.Print($"[sts2probe] warmup: {type.FullName}.{method.Name} failed: {e.GetType().Name}: {e.Message}");
                    }
                }
            }
            GD.Print($"[sts2probe] warmup done: {done} methods in {clock.ElapsedMilliseconds} ms, {failed} failed; JIT compiled " +
                     $"{System.Runtime.JitInfo.GetCompiledMethodCount(false) - jit0} methods in " +
                     $"{System.Runtime.JitInfo.GetCompilationTime(false).TotalMilliseconds - jitMs0:F0} ms");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[sts2probe] warmup aborted: {e}");
        }
    }
}
