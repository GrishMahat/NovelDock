package dev.grish.noveldock

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val classLoadElapsed = SystemClock.elapsedRealtime()
    private var volumeChannel: MethodChannel? = null
    private var intentChannel: MethodChannel? = null

    // True only while the reader asks for volume-key scrolling (reader open
    // + setting on). Otherwise volume keys behave normally system-wide.
    private var volumeScrollEnabled = false

    // Cold-start intent (SEND/VIEW/deep link): the engine isn't attached in
    // onCreate, so it waits here until Dart pulls it via getInitialIntent.
    private var pendingIntent: Map<String, String>? = null

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
        // Stash any share/deep-link intent for Dart's getInitialIntent pull.
        pendingIntent = extractPayload(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Brackets native plugin registration (GeneratedPluginRegistrant).
        val t0 = SystemClock.elapsedRealtime()
        super.configureFlutterEngine(flutterEngine)
        val dt = SystemClock.elapsedRealtime() - t0
        Log.i(TAG, "engine+plugins +${dt}ms")

        volumeChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "dev.grish.noveldock/volume_keys",
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method == "setEnabled") {
                        volumeScrollEnabled = (call.arguments as? Boolean) ?: false
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                }
            }

        intentChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "dev.grish.noveldock/intents",
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method == "getInitialIntent") {
                        result.success(pendingIntent)
                        pendingIntent = null
                    } else {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop: warm intents arrive here. Flush straight to Dart when
        // the channel is up, otherwise park for getInitialIntent.
        val payload = extractPayload(intent)
        if (payload != null) {
            if (intentChannel == null) {
                pendingIntent = payload
            } else {
                intentChannel?.invokeMethod("onIntent", payload)
            }
        }
    }

    /**
     * Turns SEND (share/file), VIEW (file/deep link/custom scheme) intents
     * into a Dart-routable map, or null when there is nothing to do.
     * File payloads are copied out of the sender's content URI into our
     * cache dir first: Dart cannot read another app's content:// URIs.
     */
    private fun extractPayload(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        if (intent.action == Intent.ACTION_MAIN &&
            intent.categories?.contains(Intent.CATEGORY_LAUNCHER) == true
        ) {
            return null
        }
        when (intent.action) {
            Intent.ACTION_SEND -> {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uri ->
                    copySharedFile(uri)?.let { path ->
                        return mapOf("kind" to "file", "path" to path)
                    }
                }
                // Browser "share link" sends the URL as text instead.
                intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                    val url = text.trim().split("\\s+".toRegex()).firstOrNull()
                    if (url != null &&
                        (url.startsWith("http://") || url.startsWith("https://"))
                    ) {
                        return mapOf("kind" to "url", "url" to url)
                    }
                }
                return null
            }
            Intent.ACTION_VIEW -> {
                val data = intent.data ?: return null
                when (data.scheme?.lowercase()) {
                    "http", "https" -> return mapOf("kind" to "url", "url" to data.toString())
                    "noveldock" -> return mapOf("kind" to "tab", "tab" to (data.host ?: ""))
                    "content", "file" -> {
                        copySharedFile(data)?.let { path ->
                            return mapOf("kind" to "file", "path" to path)
                        }
                        return null
                    }
                    else -> return null
                }
            }
            else -> return null
        }
    }

    /** Copies a shared content/file URI into our cache dir. Null on failure. */
    private fun copySharedFile(uri: Uri): String? {
        return try {
            val name =
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val idx = cursor.getColumnIndex("_display_name")
                    if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
                } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "shared"
            val safeName = "shared-${System.currentTimeMillis()}-$name".takeLast(120)
            val out = java.io.File(cacheDir, safeName)
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            out.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "copySharedFile failed: $e")
            null
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // Android delivers volume keys to the activity, never to Flutter's
        // key channel — forward them when the reader claimed scroll mode.
        if (volumeScrollEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            val method =
                if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) "volumeUp"
                else "volumeDown"
            volumeChannel?.invokeMethod(method, null)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    companion object {
        private const val TAG = "NovelDock-START"
    }
}
