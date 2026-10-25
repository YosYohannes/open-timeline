package com.opentimeline.open_timeline

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.max

class SubjectSegment(private val context: Context) {
    fun run(path: String, result: MethodChannel.Result) {
        start(
            SubjectSegmenterOptions.Builder().enableForegroundBitmap().build(),
            path,
            result,
        ) { found ->
            val subject = found.foregroundBitmap
            if (subject == null) {
                null
            } else {
                val out = File(context.cacheDir, "subject-${System.currentTimeMillis()}.png")
                out.outputStream().use { subject.compress(Bitmap.CompressFormat.PNG, 100, it) }
                out.path
            }
        }
    }

    fun detect(path: String, result: MethodChannel.Result) {
        val options = SubjectSegmenterOptions.Builder()
            .enableMultipleSubjects(
                SubjectSegmenterOptions.SubjectResultOptions.Builder().enableConfidenceMask().build()
            )
            .build()
        start(options, path, result, scale = true) { found ->
            found.subjects.map { s ->
                mapOf(
                    "x" to s.startX.toDouble(),
                    "y" to s.startY.toDouble(),
                    "w" to s.width.toDouble(),
                    "h" to s.height.toDouble(),
                )
            }
        }
    }

    private fun start(
        options: SubjectSegmenterOptions,
        path: String,
        result: MethodChannel.Result,
        scale: Boolean = false,
        reply: (com.google.mlkit.vision.segmentation.subject.SubjectSegmentationResult) -> Any?,
    ) {
        val segmenter: SubjectSegmenter = try {
            SubjectSegmentation.getClient(options)
        } catch (e: Exception) {
            result.error("segment", e.toString(), null)
            return
        }
        try {
            val bitmap = decode(path)
            val width = bitmap.width.toDouble()
            val height = bitmap.height.toDouble()
            segmenter.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { found ->
                    try {
                        val out = reply(found)
                        if (scale && out is List<*>) {
                            result.success(out.map {
                                val m = it as Map<*, *>
                                mapOf(
                                    "x" to (m["x"] as Double) / width,
                                    "y" to (m["y"] as Double) / height,
                                    "w" to (m["w"] as Double) / width,
                                    "h" to (m["h"] as Double) / height,
                                )
                            })
                        } else {
                            result.success(out)
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
                        if (waiting) "The AI model is still downloading, try again in a minute" else e.toString(),
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
        val raw = BitmapFactory.decodeFile(path, options) ?: throw IllegalStateException("Cannot read $path")
        // Flutter shows photos turned by their EXIF orientation, so the boxes must be found on the turned picture.
        val turn = orientation(path) ?: return raw
        val upright = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, turn, true)
        if (upright !== raw) raw.recycle()
        return upright
    }

    private fun orientation(path: String): Matrix? {
        val m = Matrix()
        when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.setRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.setRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.setRotate(-90f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                m.setRotate(90f)
                m.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                m.setRotate(-90f)
                m.postScale(-1f, 1f)
            }
            else -> return null
        }
        return m
    }

    private companion object {
        const val MAX_SIDE = 1024
    }
}
