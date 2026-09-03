package dev.grish.noveldock

import android.os.Build
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private val classLoadElapsed = SystemClock.elapsedRealtime()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Cold-start diagnostics: elapsed since the process was spawned,
        // measured on the native side (logcat only; not in-app).
        val sinceProcessStart = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()
        } else {
            SystemClock.elapsedRealtime() - classLoadElapsed
        }
        Log.i(TAG, "native onCreate +${sinceProcessStart}ms")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Brackets native plugin registration (GeneratedPluginRegistrant).
        val t0 = SystemClock.elapsedRealtime()
        super.configureFlutterEngine(flutterEngine)
        val dt = SystemClock.elapsedRealtime() - t0
        Log.i(TAG, "engine+plugins +${dt}ms")
    }

    companion object {
        private const val TAG = "NovelDock-START"
    }
}
