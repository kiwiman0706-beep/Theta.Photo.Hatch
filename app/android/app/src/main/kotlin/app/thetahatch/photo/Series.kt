package app.thetahatch.photo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel

/**
 * シリーズのハブ（Theta Home Hatch、無ければ Theta KidsHome Hatch）とのやり取り。
 * - 共通設定：content://<ハブ>.theta/info（ui.skin・nas.url・nas.user…）と /secret/<キー>（利用者が選んだときだけ）
 *   （Theta.Hatch.Series spec/THETA_SHARED_SETTINGS.md §4.0・§4.1）
 * - 更新：インストールの権限は持たず、ハブに頼む（spec §6.1）。ハブが無ければ Releases ページを開く
 */
object Series {
    private val HUBS = listOf("app.thetahatch.home", "app.thetahatch.kidshome")
    const val RELEASES = "https://github.com/kiwiman0706-beep/Theta.Photo.Hatch/releases/latest"

    fun hub(a: Activity): String = HUBS.firstOrNull { p ->
        runCatching { a.packageManager.getPackageInfo(p, 0) }.isSuccess
    } ?: ""

    private fun uri(hub: String, path: String) = Uri.parse("content://$hub.theta$path")

    fun handler(a: Activity) = MethodChannel.MethodCallHandler { call, result ->
        try {
            when (call.method) {
                "hub" -> result.success(hub(a))
                "version" -> result.success(a.packageManager.getPackageInfo(a.packageName, 0).versionName ?: "")
                // key → [value, by, at]。ハブが無い・読めない（共通鍵でない）ときは空
                "info" -> {
                    val out = HashMap<String, List<String>>()
                    val h = hub(a)
                    if (h.isNotEmpty()) runCatching {
                        a.contentResolver.query(uri(h, "/info"), null, null, null, null)?.use { q ->
                            val k = q.getColumnIndex("key")
                            val v = q.getColumnIndex("value")
                            val by = q.getColumnIndex("by")
                            val at = q.getColumnIndex("at")
                            while (k >= 0 && v >= 0 && q.moveToNext()) {
                                out[q.getString(k)] = listOf(
                                    q.getString(v) ?: "",
                                    if (by < 0) "" else q.getString(by) ?: "",
                                    if (at < 0) "" else q.getString(at) ?: "",
                                )
                            }
                        }
                    }
                    result.success(out)
                }
                // 利用者が「Home の設定を使う」を選んだときだけ呼ぶ
                "secret" -> {
                    val h = hub(a)
                    val key = call.argument<String>("key") ?: ""
                    if (h.isEmpty()) {
                        result.error("nohub", "Theta Home Hatch が入っていません", null)
                    } else {
                        val q = a.contentResolver.query(uri(h, "/secret/$key"), null, null, null, null)
                        if (q == null) {
                            result.error("denied", "ハブから受け取れませんでした（共通鍵で署名した版が要ります）", null)
                        } else {
                            q.use {
                                val v = it.getColumnIndex("value")
                                result.success(if (it.moveToFirst()) it.getString(if (v < 0) 0 else v) ?: "" else "")
                            }
                        }
                    }
                }
                // 「シリーズに合わせる」項目を変えたらハブにも書く
                "tell" -> {
                    val h = hub(a)
                    if (h.isNotEmpty()) runCatching {
                        val v = ContentValues().apply { put(call.argument<String>("key"), call.argument<String>("value")) }
                        a.contentResolver.update(uri(h, "/info"), v, null, null)
                    }
                    result.success(null)
                }
                // 「更新する」：ハブの更新画面を開く。無ければ Releases ページ
                "requestUpdate" -> {
                    val h = hub(a)
                    if (h.isNotEmpty()) {
                        try {
                            a.startActivity(
                                Intent("app.thetahatch.action.UPDATE").setPackage(h)
                                    .putExtra("packageName", a.packageName)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                            result.success("hub")
                            return@MethodCallHandler
                        } catch (_: ActivityNotFoundException) {
                            // 古いハブ：Releases ページへ
                        }
                    }
                    open(a, RELEASES)
                    result.success("browser")
                }
                "open" -> {
                    open(a, call.argument<String>("url") ?: RELEASES)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("error", e.message, null)
        }
    }

    private fun open(a: Activity, url: String) {
        a.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
