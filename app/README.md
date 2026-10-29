# Photo Hatch (Flutter)

「まず撮る → あとで仕分け」用の写真仕分けアプリ。運用フローは [`../docs/flow.md`](../docs/flow.md)。

## ビルド

```bash
flutter pub get
flutter build apk --release
```

出力: `build/app/outputs/flutter-apk/app-release.apk`

## 構成

- `lib/core/` … プラットフォーム非依存のロジック（XMP 書き込み・命名規則・仕分け・ジャーナル）。PC 版でも再利用する
- `lib/ui/` … 画面
- `android/.../MainActivity.kt` … MediaStore 列挙・サムネイル・メディアスキャン・全ファイルアクセス権限
