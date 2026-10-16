package com.opentimeline.open_timeline

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class VideoShrinker(private val context: Context, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null

    fun info(path: String): Map<String, Long> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            fun value(key: Int) = retriever.extractMetadata(key)?.toLongOrNull() ?: 0L
            return mapOf(
                "width" to value(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH),
                "height" to value(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT),
                "durationMs" to value(MediaMetadataRetriever.METADATA_KEY_DURATION),
            )
        } finally {
            retriever.release()
        }
    }

    fun shrink(src: String, dest: String, shortSide: Int, bitrate: Int, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Another video is being shrunk", null)
            return
        }
        pending = result
        val encoder = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
            .build()
        val t = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setEncoderFactory(encoder)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    finish { it.success(dest) }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    finish { it.error("shrink_failed", exportException.message, null) }
                }
            })
            .build()
        transformer = t
        val item = EditedMediaItem.Builder(MediaItem.fromUri(android.net.Uri.fromFile(java.io.File(src))))
            .setEffects(Effects(emptyList(), listOf(Presentation.createForShortSide(shortSide))))
            .build()
        t.start(item, dest)
        poll(t)
    }

    fun cancel() {
        transformer?.cancel()
        finish { it.success(null) }
    }

    private fun finish(reply: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        transformer = null
        reply(result)
    }

    private fun poll(t: Transformer) {
        val holder = ProgressHolder()
        main.postDelayed(object : Runnable {
            override fun run() {
                if (transformer !== t) return
                if (t.getProgress(holder) != Transformer.PROGRESS_STATE_NOT_STARTED) {
                    channel.invokeMethod("progress", holder.progress / 100.0)
                }
                main.postDelayed(this, 400)
            }
        }, 400)
    }
}
