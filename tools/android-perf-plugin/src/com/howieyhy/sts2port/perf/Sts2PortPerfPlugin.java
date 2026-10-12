package com.howieyhy.sts2port.perf;

import android.content.Context;
import android.os.Build;
import android.os.PerformanceHintManager;
import android.os.Process;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * Android Dynamic Performance Framework (ADPF) hints for the game's main thread.
 *
 * Measured on a Pixel 9a: during combat animations the Godot main thread ran on the mid cores mostly at
 * 650-1,300 MHz of 2,600, so its ~60 ms frames were CPU-bound at a fraction of the available speed. Android only
 * raises a thread's clock for an app that says what it needs: a hint session with a target frame time, fed the
 * actual time each frame took. boot.gd calls {@link #startSession} once from the main thread and
 * {@link #reportFrame} every frame. Android 12 (API 31) and newer; on older versions both do nothing.
 */
public class Sts2PortPerfPlugin extends GodotPlugin {
    private Object session; // PerformanceHintManager.Session (API 31+), kept untyped so older Androids can load us

    public Sts2PortPerfPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "Sts2PortPerf";
    }

    /** Starts a hint session for the calling thread. Returns false when the device doesn't support it. */
    @UsedByGodot
    public boolean startSession(long targetFrameNanos) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || getActivity() == null) {
            return false;
        }
        PerformanceHintManager manager =
                (PerformanceHintManager) getActivity().getSystemService(Context.PERFORMANCE_HINT_SERVICE);
        if (manager == null || manager.getPreferredUpdateRateNanos() < 0) {
            return false;
        }
        session = manager.createHintSession(new int[] {Process.myTid()}, targetFrameNanos);
        return session != null;
    }

    /** Reports how long the last frame took on the calling thread. */
    @UsedByGodot
    public void reportFrame(long actualNanos) {
        if (session != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && actualNanos > 0) {
            ((PerformanceHintManager.Session) session).reportActualWorkDuration(actualNanos);
        }
    }
}
