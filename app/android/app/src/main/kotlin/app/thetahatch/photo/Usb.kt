package app.thetahatch.photo

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.mtp.MtpConstants
import android.mtp.MtpDevice
import android.os.Handler
import android.os.Looper
import android.os.storage.StorageManager
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * 出先で USB からの取り込み。
 * - カードリーダー・USB メモリ：取り外せるストレージ（StorageVolume）。中身は Dart が dart:io で読む
 * - デジカメ・GoPro・THETA：MTP／PTP（UsbManager → MtpDevice）。一覧と、端末へのコピー（importFile）
 * 元の機器の写真は消さない・書き換えない。
 */
class Usb(private val a: Activity, private val channel: MethodChannel) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val usb get() = a.getSystemService(Context.USB_SERVICE) as UsbManager
    private val action = "${a.packageName}.USB_PERMISSION"

    private val media = setOf(
        "jpg", "jpeg", "heic", "heif", "png", "dng", "raw", "arw", "cr2", "cr3", "nef", "orf", "rw2", "raf", "gpr",
        "mp4", "mov", "insv", "insp", "360", "avi", "mts", "m4v",
    )

    fun handler() = MethodChannel.MethodCallHandler { call, result ->
        when (call.method) {
            "volumes" -> result.success(volumes())
            "mtpDevices" -> result.success(mtpDevices())
            "mtpPermission" -> permission(call.argument<String>("key") ?: "") { result.success(it) }
            "mtpList" -> {
                val key = call.argument<String>("key") ?: ""
                background(result) { mtpList(key) }
            }
            "mtpImport" -> {
                val key = call.argument<String>("key") ?: ""
                val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                background(result) { mtpImport(key, items) }
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: Exception) {
                main.post { result.error("usb", e.message, null) }
            }
        }
    }

    /** 取り外せるストレージ（カードリーダー・USB メモリ・SD カード） */
    private fun volumes(): List<Map<String, Any?>> {
        val sm = a.getSystemService(Context.STORAGE_SERVICE) as StorageManager
        return sm.storageVolumes.filter { it.isRemovable && it.state == "mounted" }.mapNotNull { v ->
            val dir = v.directory ?: return@mapNotNull null
            mapOf("key" to (v.uuid ?: dir.name), "label" to v.getDescription(a), "path" to dir.absolutePath)
        }
    }

    private fun isCamera(d: UsbDevice): Boolean = (0 until d.interfaceCount).any { i ->
        val f = d.getInterface(i)
        f.interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE ||
            (f.interfaceClass == UsbConstants.USB_CLASS_VENDOR_SPEC && f.name?.contains("MTP", true) == true)
    }

    private fun mtpDevices(): List<Map<String, Any?>> = usb.deviceList.values.filter(::isCamera).map { d ->
        mapOf(
            "key" to d.deviceName,
            "label" to listOfNotNull(d.manufacturerName, d.productName).joinToString(" ").ifBlank { "USB カメラ" },
            "granted" to usb.hasPermission(d),
        )
    }

    private fun device(key: String): UsbDevice = usb.deviceList[key] ?: throw IllegalStateException("機器が見つかりません（抜けた？）")

    private fun permission(key: String, done: (Boolean) -> Unit) {
        val d = usb.deviceList[key] ?: return done(false)
        if (usb.hasPermission(d)) return done(true)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                a.unregisterReceiver(this)
                done(i.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
            }
        }
        a.registerReceiver(receiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
        val pi = PendingIntent.getBroadcast(
            a, 0, Intent(action).setPackage(a.packageName), PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        usb.requestPermission(d, pi)
    }

    private fun <T> open(key: String, block: (MtpDevice) -> T): T {
        val d = device(key)
        val conn = usb.openDevice(d) ?: throw IllegalStateException("機器を開けません（USB の許可、またはカメラ側の USB 設定を MTP／PTP に）")
        val mtp = MtpDevice(d)
        if (!mtp.open(conn)) {
            conn.close()
            throw IllegalStateException("MTP で開けません（カメラ側の USB 設定を MTP／PTP に）")
        }
        try {
            return block(mtp)
        } finally {
            mtp.close()
        }
    }

    /** 写真・動画の一覧（フォルダは潜る）。handle・name・size・dateMs・folder */
    private fun mtpList(key: String): List<Map<String, Any?>> = open(key) { mtp ->
        val out = ArrayList<Map<String, Any?>>()
        for (storage in mtp.storageIds ?: IntArray(0)) {
            val stack = ArrayDeque<Pair<Int, String>>()
            stack.add(-1 to "") // 0xFFFFFFFF＝ルート
            while (stack.isNotEmpty()) {
                val (parent, path) = stack.removeLast()
                for (h in mtp.getObjectHandles(storage, 0, parent) ?: IntArray(0)) {
                    val info = mtp.getObjectInfo(h) ?: continue
                    val name = info.name ?: continue
                    if (info.format == MtpConstants.FORMAT_ASSOCIATION) {
                        stack.add(h to if (path.isEmpty()) name else "$path/$name")
                        continue
                    }
                    if (name.substringAfterLast('.', "").lowercase() !in media) continue
                    out.add(
                        mapOf(
                            "handle" to h,
                            "name" to name,
                            "size" to info.compressedSizeLong,
                            "dateMs" to info.dateCreated,
                            "folder" to path,
                        )
                    )
                }
            }
        }
        out
    }

    /** items: [{handle, dest}]。1 つずつ端末へコピーし、進み具合を Dart の importProgress に知らせる */
    private fun mtpImport(key: String, items: List<Map<String, Any>>): Map<String, Any> = open(key) { mtp ->
        var ok = 0
        val errors = ArrayList<String>()
        items.forEachIndexed { i, it ->
            val dest = it["dest"] as String
            val tmp = "$dest.part"
            File(dest).parentFile?.mkdirs()
            if (mtp.importFile((it["handle"] as Number).toInt(), tmp) && File(tmp).renameTo(File(dest))) {
                ok++
            } else {
                File(tmp).delete()
                errors.add(File(dest).name)
            }
            main.post { channel.invokeMethod("importProgress", mapOf("done" to i + 1, "total" to items.size)) }
        }
        mapOf("ok" to ok, "errors" to errors)
    }
}
