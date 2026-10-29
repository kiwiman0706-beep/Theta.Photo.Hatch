package photo.theta.theta_photo_hatch

import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Hatch が必要とする最小限のネイティブ機能:
 * - 「すべてのファイルへのアクセス」権限の確認・要求
 * - MediaStore からフォルダ（RELATIVE_PATH）単位で写真/動画を列挙
 * - サムネイル取得
 * - 移動後のメディアスキャン（MediaStore への反映）
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hatch/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" -> result.success(Environment.isExternalStorageManager())
                    "requestAllFilesAccess" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    "storageRoot" -> result.success(Environment.getExternalStorageDirectory().absolutePath)
                    "listMedia" -> {
                        val paths = call.argument<List<String>>("relativePaths") ?: emptyList()
                        background(result) { listMedia(paths) }
                    }
                    "thumbnail" -> {
                        val id = (call.argument<Number>("id") ?: 0).toLong()
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        val size = call.argument<Int>("size") ?: 256
                        background(result) { thumbnail(id, isVideo, size) }
                    }
                    "scanFiles" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        scanFiles(paths) { result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("native", e.message, null) }
            }
        }
    }

    private fun listMedia(relativePaths: List<String>): List<Map<String, Any?>> {
        if (relativePaths.isEmpty()) return emptyList()
        val uri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DATA,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.Files.FileColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
        )
        val placeholders = relativePaths.joinToString(",") { "?" }
        val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?,?) AND " +
            "${MediaStore.Files.FileColumns.RELATIVE_PATH} IN ($placeholders)"
        val args = arrayOf(
            MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
            MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
        ) + relativePaths.toTypedArray()

        val out = ArrayList<Map<String, Any?>>()
        contentResolver.query(uri, projection, selection, args, null)?.use { c ->
            val iId = c.getColumnIndexOrThrow(projection[0])
            val iData = c.getColumnIndexOrThrow(projection[1])
            val iName = c.getColumnIndexOrThrow(projection[2])
            val iMime = c.getColumnIndexOrThrow(projection[3])
            val iSize = c.getColumnIndexOrThrow(projection[4])
            val iType = c.getColumnIndexOrThrow(projection[5])
            val iRel = c.getColumnIndexOrThrow(projection[6])
            val iTaken = c.getColumnIndexOrThrow(projection[7])
            val iMod = c.getColumnIndexOrThrow(projection[8])
            while (c.moveToNext()) {
                val taken = if (c.isNull(iTaken)) 0L else c.getLong(iTaken)
                out.add(
                    mapOf(
                        "id" to c.getLong(iId),
                        "path" to c.getString(iData),
                        "name" to c.getString(iName),
                        "mime" to c.getString(iMime),
                        "size" to c.getLong(iSize),
                        "isVideo" to (c.getInt(iType) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO),
                        "relativePath" to c.getString(iRel),
                        "takenMs" to if (taken > 0) taken else c.getLong(iMod) * 1000,
                    )
                )
            }
        }
        return out
    }

    private fun thumbnail(id: Long, isVideo: Boolean, size: Int): ByteArray {
        val base = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val bmp = contentResolver.loadThumbnail(ContentUris.withAppendedId(base, id), Size(size, size), null)
        val bytes = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 80, bytes)
        bmp.recycle()
        return bytes.toByteArray()
    }

    private fun scanFiles(paths: List<String>, done: () -> Unit) {
        if (paths.isEmpty()) return done()
        var remaining = paths.size
        MediaScannerConnection.scanFile(this, paths.toTypedArray(), null) { _, _ ->
            main.post {
                remaining--
                if (remaining == 0) done()
            }
        }
    }
}
