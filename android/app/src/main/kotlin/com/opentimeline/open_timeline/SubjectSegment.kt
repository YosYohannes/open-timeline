package com.opentimeline.open_timeline

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.max

class SubjectSegment(private val context: Context) {
    fun run(path: String, result: MethodChannel.Result) {
        val segmenter = try {
            SubjectSegmentation.getClient(
                SubjectSegmenterOptions.Builder().enableForegroundBitmap().build()
            )
        } catch (e: Exception) {
            result.error("segment", e.toString(), null)
            return
        }
        try {
            val bitmap = decode(path)
            segmenter.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { found ->
                    try {
                        val subject = found.foregroundBitmap
                        if (subject == null) {
                            result.success(null)
                        } else {
                            val out = File(context.cacheDir, "subject-${System.currentTimeMillis()}.png")
                            out.outputStream().use { subject.compress(Bitmap.CompressFormat.PNG, 100, it) }
                            result.success(out.path)
                        }
                    } catch (e: Exception) {
                        result.error("segment", e.toString(), null)
                    } finally {
                        segmenter.close()
                    }
                }
                .addOnFailureListener { e ->
                    segmenter.close()
                    val waiting = (e as? MlKitException)?.errorCode == MlKitException.UNAVAILABLE
                    result.error(
                        "segment",
                        if (waiting) "AI removal is still downloading, try again in a minute" else e.toString(),
                        null,
                    )
                }
        } catch (e: Exception) {
            segmenter.close()
            result.error("segment", e.toString(), null)
        }
    }

    private fun decode(path: String): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_SIDE * 2) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(path, options) ?: throw IllegalStateException("Cannot read $path")
    }

    private companion object {
        const val MAX_SIDE = 1024
    }
}
