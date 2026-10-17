package com.opentimeline.open_timeline

import android.app.Activity
import android.content.Intent
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DocumentScan(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null

    fun start(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A scan is already open", null)
            return
        }
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(1)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
        pending = result
        GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
            .addOnSuccessListener { sender ->
                activity.startIntentSenderForResult(sender, REQUEST, null, 0, 0, 0)
            }
            .addOnFailureListener { e -> finish { it.error("scan", e.message, null) } }
    }

    fun handle(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        if (resultCode != Activity.RESULT_OK || data == null) {
            finish { it.success(null) }
            return true
        }
        try {
            val uri = GmsDocumentScanningResult.fromActivityResultIntent(data)?.pages?.firstOrNull()?.imageUri
            if (uri == null) {
                finish { it.success(null) }
            } else {
                val out = File(activity.cacheDir, "scan-${System.currentTimeMillis()}.jpg")
                activity.contentResolver.openInputStream(uri)!!.use { input ->
                    out.outputStream().use { input.copyTo(it) }
                }
                finish { it.success(out.path) }
            }
        } catch (e: Exception) {
            finish { it.error("scan", e.message, null) }
        }
        return true
    }

    private fun finish(reply: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        reply(result)
    }

    private companion object {
        const val REQUEST = 4417
    }
}
