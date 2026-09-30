package com.example.dashcam

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridges Dash Cam to Android's Storage Access Framework so the user can point
 * recordings at a folder of their choosing.
 *
 * Dart's dart:io cannot open a content:// URI, so a finished recording is
 * copied into the granted tree here rather than in Dart. FlutterActivity is a
 * plain android.app.Activity, not a ComponentActivity, so the classic
 * startActivityForResult/onActivityResult pair is the only option available.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "dashcam/storage"
        const val REQUEST_TREE = 4711
        const val MIME_MP4 = "video/mp4"
    }

    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "chooseFolder" -> chooseFolder(result)
                    "folderLabel" -> folderLabel(call.argument<String>("treeUri"), result)
                    "copyInto" ->
                        copyInto(
                            call.argument<String>("treeUri"),
                            call.argument<String>("sourcePath"),
                            call.argument<String>("fileName"),
                            result,
                        )
                    else -> result.notImplemented()
                }
            }
    }

    private fun chooseFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("in_progress", "A folder chooser is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        pendingPick = result
        try {
            startActivityForResult(intent, REQUEST_TREE)
        } catch (e: Exception) {
            pendingPick = null
            result.error("unavailable", e.message, null)
        }
    }

    @Deprecated("Plain Activity: the classic result API is the only one available.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_TREE) return

        val reply = pendingPick
        pendingPick = null
        val uri = data?.data
        if (reply == null || resultCode != Activity.RESULT_OK || uri == null) {
            reply?.success(null)
            return
        }

        // Without this the grant dies with the process and the next launch
        // would no longer be able to write there.
        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (flags != 0) {
            runCatching { contentResolver.takePersistableUriPermission(uri, flags) }
        }
        reply.success(uri.toString())
    }

    private fun folderLabel(treeUri: String?, result: MethodChannel.Result) {
        if (treeUri.isNullOrBlank()) {
            result.success(null)
            return
        }
        result.success(runCatching { displayName(Uri.parse(treeUri)) }.getOrNull())
    }

    private fun copyInto(
        treeUri: String?,
        sourcePath: String?,
        fileName: String?,
        result: MethodChannel.Result,
    ) {
        if (treeUri.isNullOrBlank() || sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("bad_arguments", "treeUri, sourcePath and fileName are required", null)
            return
        }
        val source = File(sourcePath)
        if (!source.isFile) {
            result.error("missing_source", "No recording found at $sourcePath", null)
            return
        }
        try {
            val tree = Uri.parse(treeUri)
            val parent = treeDocumentUri(tree)
                ?: throw IllegalStateException("The chosen folder is no longer available")
            val target = DocumentsContract.createDocument(
                contentResolver,
                parent,
                MIME_MP4,
                fileName,
            ) ?: throw IllegalStateException("The chosen folder would not accept a new file")

            contentResolver.openOutputStream(target)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Could not open $fileName for writing")

            result.success(target.toString())
        } catch (e: Exception) {
            result.error("copy_failed", e.message, null)
        }
    }

    private fun displayName(uri: Uri): String? {
        val doc = treeDocumentUri(uri) ?: return null
        contentResolver.query(
            doc,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    private fun treeDocumentUri(tree: Uri): Uri? {
        val treeId = DocumentsContract.getTreeDocumentId(tree)
        return DocumentsContract.buildDocumentUriUsingTree(tree, treeId)
    }
}
