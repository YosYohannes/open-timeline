package com.opentimeline.open_timeline

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "open_timeline/sync")
            .setMethodCallHandler { call, result ->
                val service = Intent(this, SyncKeepAliveService::class.java)
                when (call.method) {
                    "start" -> {
                        askForNotifications()
                        startForegroundService(service)
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(service)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "open_timeline/video")
        val shrinker = VideoShrinker(this, channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> try {
                    result.success(shrinker.info(call.argument<String>("path")!!))
                } catch (e: Exception) {
                    result.success(null)
                }
                "shrink" -> shrinker.shrink(
                    call.argument<String>("src")!!,
                    call.argument<String>("dest")!!,
                    call.argument<Int>("shortSide")!!,
                    call.argument<Int>("bitrate")!!,
                    result,
                )
                "cancel" -> {
                    shrinker.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
