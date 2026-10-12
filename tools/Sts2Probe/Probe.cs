using System;
using System.Diagnostics;
using Godot;

namespace Sts2Probe;

/// <summary>
/// Opt-in frame probe for finding where combat hitches come from (Mono GC vs other main-thread work).
/// Sts2Patcher inserts a call to <see cref="Install"/> at the start of NGame._Ready. It does nothing unless a file
/// named "perf_log" sits next to the packs (the same switch as boot.gd's perf log).
/// Logs, for every frame slower than 50 ms: its length and how many GCs of each generation ran during it, plus
/// managed allocations; every 5 s a summary.
/// </summary>
public static class Probe
{
    private const double SpikeMs = 50.0;
    private const double SummarySec = 5.0;
    private static readonly Stopwatch Clock = new();
    private static double _lastMs;
    private static double _nextSummaryMs;
    private static int _gen0, _gen1, _gen2;
    private static long _allocated;
    private static long _jitMethods;
    private static double _jitMs;
    private static int _summaryGcs0, _summaryGcs1, _summaryGcs2;
    private static long _summaryAllocated;

    public static void Install()
    {
        try
        {
            if (FlagFile("jit_warmup"))
                JitWarmup.Start();
            if (!FlagFile("perf_log") || Engine.GetMainLoop() is not SceneTree tree)
                return;
            Clock.Start();
            Snapshot(out _gen0, out _gen1, out _gen2, out _allocated);
            (_summaryGcs0, _summaryGcs1, _summaryGcs2, _summaryAllocated) = (_gen0, _gen1, _gen2, _allocated);
            _nextSummaryMs = SummarySec * 1000.0;
            tree.ProcessFrame += OnFrame;
            _jitMethods = System.Runtime.JitInfo.GetCompiledMethodCount(false);
            _jitMs = System.Runtime.JitInfo.GetCompilationTime(false).TotalMilliseconds;
            GD.Print($"[sts2probe] installed (GC max generation {GC.MaxGeneration}, " +
                     $"JIT so far: {_jitMethods} methods, {_jitMs:F0}ms)");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[sts2probe] install failed: {e}");
        }
    }

    /// <summary>True if a file with this name sits next to the packs (the port's testing switches).</summary>
    private static bool FlagFile(string name)
    {
        // Same lookup as boot.gd's _main_pack_dir(): --main-pack's folder, else the app's external files folder
        // (Godot doesn't always report engine arguments in GetCmdlineArgs()).
        var args = OS.GetCmdlineArgs();
        int i = Array.IndexOf(args, "--main-pack");
        string dir = i >= 0 && i + 1 < args.Length
            ? args[i + 1].GetBaseDir()
            : "/storage/emulated/0/Android/data/com.howieyhy.sts2port/files";
        return FileAccess.FileExists(dir.PathJoin(name));
    }

    private static void Snapshot(out int g0, out int g1, out int g2, out long allocated)
    {
        g0 = GC.CollectionCount(0);
        g1 = GC.CollectionCount(Math.Min(1, GC.MaxGeneration));
        g2 = GC.CollectionCount(GC.MaxGeneration);
        allocated = GC.GetTotalAllocatedBytes(false);
    }

    private static void OnFrame()
    {
        double now = Clock.Elapsed.TotalMilliseconds;
        double frame = now - _lastMs;
        _lastMs = now;
        Snapshot(out int g0, out int g1, out int g2, out long allocated);
        long jitMethods = System.Runtime.JitInfo.GetCompiledMethodCount(false);
        double jitMs = System.Runtime.JitInfo.GetCompilationTime(false).TotalMilliseconds;
        if (frame > SpikeMs)
        {
            GD.Print($"[sts2probe] frame {frame:F0}ms gc {g0 - _gen0}/{g1 - _gen1}/{g2 - _gen2} " +
                     $"jit {jitMethods - _jitMethods} methods {jitMs - _jitMs:F0}ms");
        }
        (_gen0, _gen1, _gen2, _allocated, _jitMethods, _jitMs) = (g0, g1, g2, allocated, jitMethods, jitMs);

        if (now >= _nextSummaryMs)
        {
            GD.Print($"[sts2probe] 5s: gc {g0 - _summaryGcs0}/{g1 - _summaryGcs1}/{g2 - _summaryGcs2} " +
                     $"alloc {(allocated - _summaryAllocated) / 1048576.0:F1}MB heap {GC.GetTotalMemory(false) / 1048576}MB " +
                     $"pause total {GC.GetTotalPauseDuration().TotalMilliseconds:F0}ms");
            (_summaryGcs0, _summaryGcs1, _summaryGcs2, _summaryAllocated) = (g0, g1, g2, allocated);
            _nextSummaryMs = now + SummarySec * 1000.0;
        }
    }
}
