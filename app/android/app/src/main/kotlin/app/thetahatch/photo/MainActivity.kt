package app.thetahatch.photo

import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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
import java.io.File
import java.util.concurrent.Executors

/**
 * Hatch が必要とする最小限のネイティブ機能:
 * - 「すべてのファイルへのアクセス」権限の確認・要求
 * - MediaStore からフォルダ（RELATIVE_PATH）単位で写真/動画を列挙
 * - サムネイル取得
 * - 移動後のメディアスキャン（MediaStore への反映）
 * - Wi-Fi かどうか（NAS へのアップは Wi-Fi のときだけ）
 * - ビューアとして開かれたとき（ACTION_VIEW）の写真
 * ハブとのやり取りは Series.kt、USB からの取り込みは Usb.kt。
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "hatch/series").setMethodCallHandler(Series.handler(this))
        val usbChannel = MethodChannel(messenger, "hatch/usb")
        usbChannel.setMethodCallHandler(Usb(this, usbChannel).handler())
        MethodChannel(messenger, "hatch/native")
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
                        val prefix = call.argument<Boolean>("prefix") ?: false
                        background(result) { listMedia(paths, prefix) }
                    }
                    "isWifi" -> result.success(isWifi())
                    "viewIntent" -> {
                        val uri = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.data
                        background(result) { uri?.let { resolve(it) } }
                    }
                    "thumbnail" -> {
                        val id = (call.argument<Number>("id") ?: 0).toLong()
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        val size = call.argument<Int>("size") ?: 256
                        background(result) { thumbnail(id, isVideo, size) }
                    }
                    "decode" -> {
                        val path = call.argument<String>("path") ?: ""
                        val max = call.argument<Int>("max") ?: 2560
                        background(result) { decode(path, max) }
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

    /** Wi-Fi（か有線）につながっていて、従量制でないとき */
    private fun isWifi(): Boolean {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        val local = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        // Tailscale（VPN）越しでも、下の回線が Wi-Fi なら NOT_METERED になる
        return local || caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    /** ACTION_VIEW の content:// を、読めるファイルのパスにする（MediaStore にあればその場所、無ければ一時コピー） */
    private fun resolve(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        runCatching {
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0)?.let { if (File(it).canRead()) return it }
            }
        }
        val name = runCatching {
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        }.getOrNull() ?: "view"
        val out = File(cacheDir, "view/$name").apply { parentFile?.mkdirs() }
        contentResolver.openInputStream(uri)?.use { i -> out.outputStream().use { i.copyTo(it) } } ?: return null
        return out.absolutePath
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun listMedia(relativePaths: List<String>, prefix: Boolean): List<Map<String, Any?>> {
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
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
        )
        val rel = MediaStore.Files.FileColumns.RELATIVE_PATH
        // prefix：DCIM/ThetaCamera/ なら DCIM/ThetaCamera/<フォルダ>/ も含める
        val where = if (prefix) relativePaths.joinToString(" OR ") { "$rel LIKE ? ESCAPE '\\'" }
        else "$rel IN (${relativePaths.joinToString(",") { "?" }})"
        val values = if (prefix) relativePaths.map { it.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%" }
        else relativePaths
        val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?,?) AND ($where)"
        val args = arrayOf(
            MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
            MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
        ) + values.toTypedArray()

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
            val iW = c.getColumnIndexOrThrow(projection[9])
            val iH = c.getColumnIndexOrThrow(projection[10])
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
                        "width" to if (c.isNull(iW)) 0 else c.getInt(iW),
                        "height" to if (c.isNull(iH)) 0 else c.getInt(iH),
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

    /**
     * ビューア用に写真を読む（HEIF・回転（EXIF の向き・irot）は OS のデコーダに任せる）。長い辺を max 以下に。
     * HEIF の clap（表示範囲）を OS が切るかは機種しだいなので、切るのは Dart 側で、読めた縦横を見て決める。
     */
    private fun decode(path: String, max: Int): Map<String, Any> {
        val src = android.graphics.ImageDecoder.createSource(File(path))
        val bmp = android.graphics.ImageDecoder.decodeBitmap(src) { d, info, _ ->
            val w = info.size.width
            val h = info.size.height
            val scale = minOf(1.0, max.toDouble() / maxOf(w, h))
            if (scale < 1.0) d.setTargetSize((w * scale).toInt().coerceAtLeast(1), (h * scale).toInt().coerceAtLeast(1))
            d.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
        }
        val bytes = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 90, bytes)
        val out = mapOf("bytes" to bytes.toByteArray(), "width" to bmp.width, "height" to bmp.height)
        bmp.recycle()
        return out
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
