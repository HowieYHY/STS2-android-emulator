package com.howieyhy.sts2port.perf;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.os.PerformanceHintManager;
import android.os.Process;
import android.view.View;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * The port's Android-side helpers (the singleton name is historical: it started with performance hints only).
 *
 * <p>{@link #installPortPack} hands the overlay the port's own code shipped in this APK; see port_loader.gd.
 *
 * <p>Crash log: the phone's logcat buffer holds only a few minutes, and logd prunes the chattiest app first, so after a
 * crash (issue #6, 16 Oct: SIGABRT with no tombstone) the game's last lines and the runtime's abort message were gone.
 * At startup a logcat reader for this process alone writes them to files/logs/logcat.txt, where
 * scripts/crash-report.ps1 collects them. An app may read its own log lines without any permission.
 *
 * <p>Android Dynamic Performance Framework (ADPF) hints for the game's main thread:
 *
 * Measured on a Pixel 9a: during combat animations the Godot main thread ran on the mid cores mostly at
 * 650-1,300 MHz of 2,600, so its ~60 ms frames were CPU-bound at a fraction of the available speed. Android only
 * raises a thread's clock for an app that says what it needs: a hint session with a target frame time, fed the
 * actual time each frame took. boot.gd calls {@link #startSession} once from the main thread and
 * {@link #reportFrame} every frame. Android 12 (API 31) and newer; on older versions both do nothing.
 */
public class Sts2PortPerfPlugin extends GodotPlugin {
    private static final int KEPT_LOGCAT_SESSIONS = 5;

    private Object session; // PerformanceHintManager.Session (API 31+), kept untyped so older Androids can load us
    private java.lang.Process logcat;

    public Sts2PortPerfPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "Sts2PortPerf";
    }

    @Override
    public View onMainCreate(Activity activity) {
        startLogcat(activity);
        return null;
    }

    @Override
    public void onMainDestroy() {
        if (logcat != null) {
            logcat.destroy();
        }
    }

    /**
     * Starts `logcat` for this process (main, system and crash buffers) writing to logs/logcat.txt. The previous
     * session's file is renamed logcat-&lt;time&gt;.txt first, keeping the newest few: after a crash the user usually
     * relaunches the game before the PC collects the logs.
     *
     * <p>Its stdout goes straight to the file. `logcat -f` (which can rotate) writes in 4 KB blocks, and when the app
     * dies Android kills logcat with it, so the last lines before a crash, the ones that matter, were lost (measured on
     * the phone with a force-stop). A session writes a few MB an hour.
     */
    private void startLogcat(Activity activity) {
        File base = activity.getExternalFilesDir(null);
        File dir = base == null ? null : new File(base, "logs");
        if (dir == null || (!dir.isDirectory() && !dir.mkdirs())) {
            return;
        }
        File current = new File(dir, "logcat.txt");
        if (current.exists()) {
            String stamp = new java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.ROOT)
                    .format(new java.util.Date(current.lastModified()));
            current.renameTo(new File(dir, "logcat-" + stamp + ".txt"));
        }
        File[] old = dir.listFiles((d, name) -> name.matches("logcat-\\d{8}-\\d{6}\\.txt"));
        if (old != null && old.length > KEPT_LOGCAT_SESSIONS) {
            Arrays.sort(old); // the names sort by time
            for (int i = 0; i < old.length - KEPT_LOGCAT_SESSIONS; i++) {
                old[i].delete();
            }
        }
        try {
            logcat = new ProcessBuilder("logcat", "-b", "main,system,crash", "-v", "threadtime",
                    "--pid=" + Process.myPid())
                    .redirectOutput(current)
                    .redirectError(new File(dir, "logcat-errors.txt"))
                    .start();
        } catch (IOException | RuntimeException e) {
            logcat = null;
        }
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

    /**
     * Copies the port code pack (assets/sts2port/port.pck, added by build-perf-plugin.ps1) next to the game's packs,
     * where Godot can mount it, and returns its path; "" if this APK has none or the copy failed. It's copied on every
     * launch (a few KB), so it always matches the installed APK.
     */
    @UsedByGodot
    public String installPortPack() {
        Activity activity = getActivity();
        File dir = activity == null ? null : activity.getExternalFilesDir(null);
        if (dir == null) {
            return "";
        }
        File out = new File(dir, "port.pck");
        File tmp = new File(dir, "port.pck.tmp");
        try (InputStream in = activity.getAssets().open("sts2port/port.pck");
                OutputStream copy = new FileOutputStream(tmp)) {
            byte[] buffer = new byte[64 * 1024];
            for (int n; (n = in.read(buffer)) > 0; ) {
                copy.write(buffer, 0, n);
            }
        } catch (IOException e) {
            tmp.delete();
            return "";
        }
        if (!tmp.renameTo(out)) {
            out.delete();
            if (!tmp.renameTo(out)) {
                return "";
            }
        }
        return out.getAbsolutePath();
    }

    /** Reports how long the last frame took on the calling thread. */
    @UsedByGodot
    public void reportFrame(long actualNanos) {
        if (session != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && actualNanos > 0) {
            ((PerformanceHintManager.Session) session).reportActualWorkDuration(actualNanos);
        }
    }
}
