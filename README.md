# Theta Photo Hatch

「まず撮る → あとで仕分け」。スマホで撮った写真（Theta Camera Hatch・USB でつないだカメラの物も）を、日付ごとの一覧からまとめて選んで仕分けるアプリ。Theta Hatch シリーズの 1 つです。

- 仕分け先は端末の固定フォルダ（`Pictures/Hatch_FamilyShare` など）。Amazon フォト・Synology Photos のバックアップはフォルダ単位で任せる
- 名前を `<撮影日時>_<イベント>_<元の名前>` に付け直し、分類・イベント・☆・キーワード・コメントを **XMP**（JPEG は中、ほかは `.xmp`）に書く。ほかのソフトでも読める
- NAS（Synology、Tailscale 経由）へ直接上げることもできる：`<アップ先>/<年>/<YYYY-MM-DD> <イベント>/`（Wi-Fi のときだけ）
- USB から取り込み（デジカメ・GoPro・THETA・カードリーダー）
- ビューア：HEIF の clap（表示範囲）、THETA などの 360° 写真

運用のしかたは [docs/flow.md](docs/flow.md)、ファイルの決まりは [docs/file-management.md](docs/file-management.md)、実機で確かめていないことは [TESTING.md](TESTING.md)。

## 入れ方・更新

- [Releases](https://github.com/kiwiman0706-beep/Theta.Photo.Hatch/releases/latest) の `ThetaPhotoHatch-<版>.apk`（Android 11 以降）
- 更新は Theta Home Hatch・KidsHome Hatch（ハブ）がまとめて行う。ハブが無ければ、設定の「更新を確認」で Releases を開く
- 0.1.0（Photo Hatch、`photo.theta.theta_photo_hatch`）からは、アンインストールしてから入れる（写真と XMP は端末に残る）

## ビルド

```bash
cd app
flutter pub get
flutter test
flutter build apk --release
```

- Release は GitHub Actions（`.github/workflows/release.yml`）：`app/pubspec.yaml` の版を上げて `main` に push すると、タグ `v<版>` と Release を作る。署名はシリーズ共通の鍵（Secret 4 つ：`ANDROID_KEYSTORE_B64`・`ANDROID_KEYSTORE_PASSWORD`・`ANDROID_KEY_ALIAS`・`ANDROID_KEY_PASSWORD`）
- 手元で共通鍵を使うなら `app/android/key.properties`（Git 管理外。`storeFile`・`storePassword`・`keyAlias`・`keyPassword`）。無ければデバッグ鍵（ハブからは入らない）

## 構成

- `app/lib/core/` … 仕分け・XMP・命名・Camera 連携・clap・360°・USB・NAS（PC 版でも使う）
- `app/lib/ui/` … 画面（`hud/` はシリーズのスキン）
- `app/android/.../app/thetahatch/photo/` … MediaStore・サムネイル・USB（`Usb.kt`）・ハブ（`Series.kt`）

シリーズ共通の決まりは [Theta.Hatch.Series](https://github.com/kiwiman0706-beep/Theta.Hatch.Series)。
