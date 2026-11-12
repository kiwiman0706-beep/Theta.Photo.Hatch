# Theta Photo Hatch

「まず撮る → あとで仕分け」の写真アプリ（Flutter、`app/`）。仕分け・タグ・☆・イベントは XMP、NAS（Synology）へは File Station で。
詳しくは README.md、運用は docs/flow.md、実機で確かめていないことは TESTING.md。

- アプリ ID `app.thetahatch.photo`。Release は `main` への push で `release.yml` が作る（版は `app/pubspec.yaml`、本文は `docs/releases/v<版>.md`）
- スキンの色は `app/lib/ui/hud/skins.g.dart`（手で直さない。`cd app && python tool/gen_skins.py <Theta.Hatch.Series>/design/skins/skins.json`）
- テスト：`cd app && flutter analyze && flutter test`
- Theta Camera Hatch の形式（`DCIM/ThetaCamera/`・`Documents/ThetaCamera/` の `.theta.json`・`.xmp`、HEIF の clap）は Camera のリポジトリの PORTABLE_METADATA.md が正本

## Theta Hatch シリーズ共通（必ず参照）

このアプリは Theta Hatch シリーズの 1 つです。シリーズ共通の仕様・デザイン・鍵の決まりは
GitHub の kiwiman0706-beep/Theta.Hatch.Series にあり、このリポジトリの docs より優先します。

- 作業を始める前に、Theta.Hatch.Series を読める状態にする
  （クラウドのスレッドでは add_repo で kiwiman0706-beep/Theta.Hatch.Series を追加して clone する）
- 読むもの：
  - `spec/THETA_HATCH_SPEC.md`（共通仕様）、`spec/THETA_VAULT_SPEC.md`、`spec/THETA_SHARED_SETTINGS.md`、`spec/THETA_GOOGLE_SETUP.md`
  - `design/README.md`（スキン：system・dark・light・pop・alert・scifi。色は `design/skins/skins.json`）
  - `spec/THETA_HATCH_SPEC.md` §6.1（アプリ内自動更新は必須）、`docs/MIGRATION.md`・`catalog/apps.json`（このアプリの目標の ID・リポジトリ名）
  - `secrets/README.md`（署名鍵はシリーズ共通。Secret の名前は ANDROID_KEYSTORE_B64・ANDROID_KEYSTORE_PASSWORD・ANDROID_KEY_ALIAS・ANDROID_KEY_PASSWORD）
- 共通仕様の写しをこのリポジトリに増やさない（変えるときは Theta.Hatch.Series 側を直す）
- 鍵・パスワード・API キーをリポジトリに入れない
- 移行や大きな変更の方針と進み具合は、Theta.Hatch.Series の `progress/<id>.md` に書く（書き方は `progress/_TEMPLATE.md`。自分のアプリのファイルだけを触る）
- 作品の版や概要が変わったら、Theta.Hatch.Series の README の一覧も直す
