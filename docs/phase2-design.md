# フェーズ2 設計: ルームと共有（CloudKit）

前提（決定済み）: 自前サーバーなし / 友達とルーム（最大12人程度）/ 線は1時間で曇って消え、ログは残さない /
背景写真はルームで1枚共有・誰でも変更可・変更しても線は残す / アプリ内アカウントなし（ニックネームのみ）。

Apple Developer Program 加入後に着手する（無料アカウントでは CloudKit・プッシュ・TestFlight が使えない）。

## 1. データの持ち方

**ルーム = 作成者のプライベート DB 上の専用ゾーン 1 つ**を、ゾーンごと共有（`CKShare(recordZoneID:)`）する。
メンバーは共有 DB（`sharedCloudDatabase`）から同じゾーンを読み書きする。

```
Zone "room-<UUID>"（作成者のプライベート DB）
├── CKShare          … 招待リンク。参加者一覧と権限（全員 readWrite）
├── Room   ×1        … name, background (CKAsset), backgroundUpdatedAt
├── Member ×人数     … nickname。recordName = 参加者の userRecordID
└── Stroke ×n        … points, drips（下記）
```

| レコード | フィールド | メモ |
|---|---|---|
| Room | `name: String`, `background: CKAsset` | 背景は長辺 1290px の JPEG に縮小して 300KB 前後。誰でも上書き可 = 最後に変えた人の写真 |
| Member | `nickname: String` | iCloud の氏名は使わない（匿名方針）。各自が自分のレコードだけ書く |
| Stroke | `points: Bytes`, `drips: Bytes` | `points` は 0...1 正規化座標を Float16 ×2 で詰めたバイト列（200点で 800B）。`drips` は作者の端末で決めた乱数を JSON で。全員に同じ水滴が垂れる |

- 線と背景は `encryptedValues` / CKAsset で保存し、Apple 側でも中身を読めないようにする。
- 作者は CloudKit が自動で付ける `creatorUserRecordID`、時刻は**サーバーの `creationDate`** を使う。
  端末の時計がずれていても、全員の窓で同じタイミングで曇り直す。

## 2. 同期

- **CKSyncEngine**（iOS 17+）を使う。変更の取得、サブスクリプション登録、サイレントプッシュでの起床、
  再試行をまとめて面倒を見てくれるので、自前で書くのは「レコード ⇄ ローカルの Stroke」の変換だけ。
- 同期の単位は**描き終えた線 1 本**。描いている途中の線は送らない（反映は数秒遅れる。要件で合意済み）。
- 受け取った線は、今と同じローカルの `strokes` 配列に入れる。描画・曇り直し・水滴のコードはそのまま使える。

## 3. 消えた線の後始末

CloudKit には自動削除（TTL）がなく、定期実行できるサーバーもない。そこで:

- **表示**: 各端末は `creationDate` から1時間を過ぎた線を描かない（今と同じ）。
- **削除**: アプリを開いた端末が、ルーム内の期限切れ Stroke を見つけ次第まとめて削除する（誰の線でも消してよい）。
  誰も開かなければ残るが、1本 1KB 程度なので実害はない。

## 4. 招待と参加

- 作成者が「招待」→ `ShareLink` / `UICloudSharingController` で CKShare の URL を LINE などで送る。
- 受け取った人が URL を開くと comado が起動し、`userDidAcceptCloudKitShareWith` で参加。初回はニックネーム入力。
- Info.plist に `CKSharingSupported = YES`（xtool.yml の `infoPath` で指定）。
- 12人上限はアプリ側で、参加者数を見て招待ボタンを無効にする。
- 退出: 参加者は共有から抜ける。作成者が抜ける（ゾーン削除）とルームは消える。

## 5. ウィジェット

- 同期でルームが更新されたら、窓の状態を画像にして App Group に保存し `WidgetCenter.reloadTimelines` を呼ぶ。
- 更新のきっかけは CloudKit のサイレントプッシュ。**iOS が回数を絞るので即時には映らない**（数分〜遅れることがある）。
- xtool のバグ（[#313](https://github.com/xtool-org/xtool/issues/313)）が直っていることが前提。

## 6. 通報・ブロック（App Store 審査 1.2）

- **ブロック**: 相手の `creatorUserRecordID` を端末に保存し、その人の線を描かない。
- **ルームから外す**: 作成者は参加者を共有から削除できる。
- **通報**: サーバーがないので、運営宛てのメール（`mailto:`、ルーム ID と相手 ID を本文に入れる）で受ける。
  審査で足りないと言われたら、そのときに受付先を用意する。

## 7. コストと制約

- CloudKit の容量は**ルーム作成者の iCloud ストレージ**を消費する（背景 300KB + 線 数KB 程度）。
- 公開データベースは使わないので、開発者側の CloudKit 使用量はほぼゼロ。
- iCloud にサインインしていない人は使えない。初回起動時に案内を出す。

## 未決事項

- ルーム名は必要か（なくてもよい。参加中のルームが1つなら不要）
- 1人が複数のルームに入れるか（入れるならルームの切り替え UI が必要）
- ウィジェットに映すのは「どのルーム」か（複数ルームの場合）
