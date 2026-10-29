# Theta.Photo.Hatch — 運用フロー（Android 版 v0.1）

## 全体の流れ

```
 ① 撮る                ② 仕分ける（Photo Hatch）            ③ 各アプリが自動アップ            ④ 端末から消す
 ─────────            ──────────────────────────           ───────────────────────          ─────────────
 カメラ                未処理一覧（DCIM/Camera 等）          Amazonフォト ← Hatch_FamilyShare   Synology Photos
   │                     │ タップ / 日付タップで選択          Synology    ← Hatch_* 全部        「空き容量を確保」
   ▼                     ▼                                   みてね      ← 共有ボタンで手動
 DCIM/Camera/  ──▶  Pictures/Hatch_FamilyShare/
                    Pictures/Hatch_Family/
                    Pictures/Hatch_Memo/
                    Pictures/Hatch_Private/
                    Pictures/Hatch_Trash/   (.nomedia / どこにも上がらない)
```

- **未処理 = DCIM/Camera などにまだ残っている写真**。仕分けると移動するので一覧から消え、空になったら完了。
- 仕分け時に同時に行うこと
  - リネーム：`20261029_103512_布引ハーブ園_PXL_20261029_013512345.jpg`
  - XMP 書き込み：分類・イベント名・☆・キーワード・元ファイル名
    - JPEG → ファイル内に埋め込み（既存の XMP＝Motion Photo 情報などは保持）
    - HEIC / 動画など → 同名の `.xmp` サイドカー
  - ジャーナル記録（直前の仕分けを「元に戻す」可能）

## なぜ「仕分け先フォルダ」を固定にするのか

Android の Amazon フォト / Synology Photos は「バックアップするフォルダ」を **フォルダ単位** で選ぶ。
イベントごとにフォルダを作ると、毎回各アプリで設定し直す必要がある。
そこで端末上は「アップロード先ごとの固定フォルダ」にして、**イベント名はファイル名と XMP に持たせる**。
NAS に上がった後でイベントフォルダ（`2026-10-29_布引ハーブ園/`）に整理し直すのは将来の PC/NAS 版の仕事。

## 初期設定（1回だけ）

| アプリ | 設定 |
|---|---|
| Photo Hatch | 「すべてのファイルへのアクセス」を許可 |
| Amazon フォト | 自動保存：**カメラをオフ**、`Hatch_FamilyShare` だけオン |
| Synology Photos | バックアップ対象：**カメラをオフ**、`Hatch_FamilyShare` `Hatch_Family` `Hatch_Memo` `Hatch_Private` をオン |
| みてね | Photo Hatch の「仕分け済み → 家族・共有」で写真を選び、共有 → みてね |
| Google フォト等 | 使っているならバックアップを **オフ**（事故写真などが勝手に上がるのを防ぐ） |

> 注意: カメラフォルダをバックアップ対象から外すので、**仕分けるまでは端末にしか無い**。
> こまめに仕分ける運用にするか、気になるならカメラも Synology に上げる（ただしリネーム後に二重アップになる）。

## 端末から消すタイミング

- Synology Photos の「空き容量を確保」は **Synology にバックアップ済みのものを端末から削除** する。
- `Hatch_FamilyShare` は Amazon フォトへのアップも必要なので、Amazon 側のアップロード完了を確認してから実行する。
- 将来：Photo Hatch が Synology の File Station API で「NAS に同じファイルがあるか」を確認してから削除する機能。

## 要検証

- [ ] Synology Photos のバックアップで、端末のフォルダ名ごとに NAS 側でも分かれるか（`MobileBackup/<端末>/Hatch_Family/` 等）
- [ ] `Hatch_Private` だけ個人スペース、その他を共有スペースに送り分けできるか（できなければ NAS 側で移動）
- [ ] Amazon フォト Android 版のフォルダ選択 UI（機種・バージョンで表記が違う）
- [ ] Synology Photos / Amazon フォトが XMP の キーワード・Rating を読むか

## 今後

1. **PC 版（Windows / Mac）**：同じ Flutter コードで、GoPro の SD カードを仕分けて NAS にアップ。
2. **NAS 整理**：XMP を読んで `Family/2026/2026-10-29_布引ハーブ園/` に再配置。
3. **Synology 連携**：File Station API（公式）でアップロード確認、Synology Photos API（非公式）でタグ/アルバムをミラー。
4. **Obsidian ノート**：イベントごとに Markdown ノートを生成（下記）。

## Obsidian 形式との関係（Theta.Hatch シリーズとの整合）

- **写真そのものの正は XMP**（ファイルと一緒に Synology / Amazon / PC へ移動しても失われない）。
- **Obsidian は「イベントの索引・日記」層** として相性が良い。写真は Vault に入れず、NAS 上のパスで参照する。

```markdown
---
type: photo-event
date: 2026-10-29
event: 布引ハーブ園
category: family_share
tags: [長男, ハーブ]
starred: 3
count: 42
nas_path: /photo/Family/2026/2026-10-29_布引ハーブ園/
shared: [amazon-photos, mitene]
---
# 20261029｜布引ハーブ園

- ☆ 20261029_103512_布引ハーブ園_PXL_….jpg
- …
```

- Dataview で「☆ の多いイベント」「みてね未送信のイベント」などが一覧できる。
- 生成タイミングは「イベント名付きで仕分けた時」にスマホで追記、または PC/NAS 版で XMP から一括生成（再生成可能＝キャッシュ扱い）。
