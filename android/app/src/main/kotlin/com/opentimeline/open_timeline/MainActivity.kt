package com.opentimeline.open_timeline

import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
