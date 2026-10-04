package de.loicezt.stickers

import android.app.Activity
import android.content.Intent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.DataInputStream
import java.io.File

/** Single MIME filtering keeps ordinary photos out of the same Android gallery picker. */
class GifPicker(private val activity: Activity, private val scope: CoroutineScope) {
    private var pending: MethodChannel.Result? = null

    fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("PICKER_ACTIVE", "The GIF picker is already open", null)
            return
        }
        pending = result
        try {
            val request = PickVisualMediaRequest.Builder()
                .setMediaType(ActivityResultContracts.PickVisualMedia.SingleMimeType("image/gif"))
                .build()
            activity.startActivityForResult(
                ActivityResultContracts.PickVisualMedia().createIntent(activity, request), REQUEST_CODE
            )
        } catch (e: Exception) {
            pending = null
            result.error("GIF_PICKER", e.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        scope.launch {
            var file: File? = null
            try {
                val path = withContext(Dispatchers.IO) {
                    val output = File.createTempFile("sticker_gif_", ".gif", activity.cacheDir)
                    file = output
                    activity.contentResolver.openInputStream(uri).use { input ->
                        checkNotNull(input) { "Could not read the selected GIF" }
                        output.outputStream().use { input.copyTo(it) }
                    }
                    val header = output.inputStream().use {
                        val bytes = ByteArray(6)
                        DataInputStream(it).readFully(bytes)
                        bytes.toString(Charsets.US_ASCII)
                    }
                    require(header == "GIF87a" || header == "GIF89a") { "The selected file is not a GIF" }
                    output.path
                }
                result.success(path)
            } catch (e: Exception) {
                file?.delete()
                result.error(if (e is IllegalArgumentException) "INVALID_GIF" else "GIF_PICKER", e.message, null)
            }
        }
        return true
    }

    companion object {
        private const val REQUEST_CODE = 6107
    }
}
