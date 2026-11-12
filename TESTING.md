# 確かめたこと・まだのこと

## 0.2.0

自動のテスト（`cd app && flutter analyze && flutter test`）：XMP の書き込み・読み戻し、ファイル名、clap の範囲（サイドカー・HEIF の ispe/clap・回転）、Camera のサイドカー、360° の判定、NAS のフォルダ名。

**実機ではまだ何も確かめていません（未確認）。** 確かめること：

- [ ] 0.1.0 をアンインストール → 0.2.0 を入れる。`Pictures/Hatch_*` の写真と XMP が残る
- [ ] 「すべてのファイルへのアクセス」→ 未処理に DCIM/Camera・DCIM/ThetaCamera/<フォルダ>/・スクリーンショットが出る
- [ ] ハブ：Home の Hatch ドロワーに出て更新できる。設定の「更新を確認」→ Home の更新画面が開く（Home が無ければ Releases）
- [ ] ハブ：Home のスキンに合わせて色が変わる。「Home Hatch の設定を使う」で NAS の設定を受け取れる（共通鍵の版どうしでだけ動く）
- [ ] USB：GoPro・THETA・デジカメ（MTP／PTP）が一覧に出て、許可 → 一覧 → 取り込みができる。カードリーダーも
- [ ] USB：取り込んだ物が未処理（Pictures/Hatch_Inbox/<機器>/）に出て、撮影日で並ぶ。2 回目は飛ばす
- [ ] NAS：Tailscale 経由でログイン（確認コード 1 回 → 次から要らない）。Wi-Fi で上げると `<アップ先>/<年>/<日付 イベント>/` にでき、サイドカーも並ぶ。モバイル回線では上げない
- [ ] NAS：`/home/Photos/…`（個人スペース）に上げられるか（File Station での `/home` の扱い）
- [ ] Camera：仕分けでイベント・☆・タグ・コメントが XMP に入る。「コピー」なら Camera のギャラリーに残り、未処理から消える
- [ ] clap：Camera の HEIF（1:1・フル）がビューアで正しい範囲に切れる。「全体」で全部見える。縦持ち（irot 270°）も
- [ ] 360°：THETA の写真が 360° で見られる。端末の向きで動かせる
- [ ] Camera のサムネイル → Theta Photo Hatch で開く（ACTION_VIEW を受ける）

## 分かっている制限

- 360° 動画は 360° では見られない（サムネイルだけ）
- USB の MTP は機種しだい。Mac・iPhone は未対応
- Windows・Mac 版はまだ作っていない（`app/windows`・`app/macos` は作成のみ）
