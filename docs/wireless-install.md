# xtool + Tailscale でワイヤレスに iPhone へインストールする

WSL2 (Linux) から USB ケーブルなしで、xtool でビルドしたアプリを iPhone にインストールする手順。
PC と iPhone が別のネットワーク（例: 会社の有線 LAN と携帯の Wi-Fi）でも動く。

## 仕組み

- iOS 17 以降は、従来の接続窓口 lockdownd（TCP 62078）をネットワーク越しには使わせない。
  接続は受け付けるが最初の要求で切断されるので、xtool の `--network` や netmuxd は使えない。
- 代わりに、Xcode と同じ RemotePairing（TCP 49152）で暗号化トンネルを張り、その中の
  installation_proxy でインストールする（`scripts/tailscale-device.py`）。
- トンネルは pymobiledevice3 のユーザー空間実装を使うので root 不要。
- Tailscale は PC と iPhone を同じ仮想ネットワークに入れて、49152 番ポートに届かせるために使う。

## 必要なもの

| もの | 用途 |
|---|---|
| xtool（`xtool setup` 済み） | ビルドと署名 |
| [uv](https://docs.astral.sh/uv/) | スクリプトの実行（pymobiledevice3 は自動で入る） |
| Tailscale（PC と iPhone を同じアカウントで） | ネットワークの経路 |
| usbipd-win（Windows） | 初回だけ USB で iPhone を WSL に渡す |
| USB ケーブル | 初回だけ |

## 初回のみ（USB が必要）

1. **Tailscale を両方に入れる**
   - WSL: `sudo tailscale login` で個人アカウントにログイン
   - iPhone: App Store の Tailscale で同じアカウントにログインし、VPN をオン
   - `tailscale status` で iPhone の IP（`100.x.x.x`）を控える

2. **iPhone を USB で WSL に渡す**（Windows の管理者 PowerShell）

   ```
   usbipd list                       # iPhone の BUSID を確認
   usbipd bind --busid <BUSID>       # 初回だけ
   usbipd attach --wsl --busid <BUSID>
   ```

   iPhone に「このコンピュータを信頼しますか？」が出たら「信頼」。
   WSL で `idevice_id -l` に UDID が出れば OK。

3. **xtool で一度インストールする**（端末の登録と、デベロッパモードの確認を兼ねる）

   ```
   xtool dev --usb
   ```

   iPhone の「設定 > プライバシーとセキュリティ > デベロッパモード」をオンにし、
   「設定 > 一般 > VPN とデバイス管理」で開発元を信頼する。

4. **RemotePairing のペアリング記録を作る**（iPhone 側の操作は不要）

   ```
   USBMUXD_SOCKET_ADDRESS=/var/run/usbmuxd uvx pymobiledevice3 lockdown remotepairing --pair
   ```

   `~/.local/share/pymobiledevice3/remote_<UDID>.plist` ができる。以降 USB は不要。
   （WSL では pymobiledevice3 が Windows 側の usbmuxd を探しに行くので、`USBMUXD_SOCKET_ADDRESS` の指定が必要）

## 毎回の手順（ワイヤレス）

```
xtool dev build --sign --ipa
uv run scripts/tailscale-device.py <iPhone の Tailscale IP> <UDID> install xtool/comado.ipa
```

- 1 行目: 署名済み ipa を `xtool/comado.ipa` に出力（端末への接続は不要）
- 2 行目: Tailscale 越しにインストール。`インストール完了` と出れば成功

無料の Apple ID で署名したアプリは 7 日で起動できなくなるので、同じ手順で入れ直す。

### スクリーンショット

```
uv run scripts/tailscale-device.py <iPhone の Tailscale IP> <UDID> screenshot out.png
```

初回は Developer Disk Image のダウンロードとマウントが走る。iPhone のロックを解除しておくこと。

## うまくいかないとき

| 症状 | 対処 |
|---|---|
| `TimeoutError` / 接続できない | iPhone の Tailscale アプリを開き、VPN をオフ→オン。`tailscale ping <IP>` で疎通を確認 |
| `tailscale status` で iPhone が `offline` | 同上。iOS はバックグラウンドで VPN を止めることがある |
| 49152 に繋がらない | iPhone がどこかの Wi-Fi に接続しているか確認（モバイル回線だけだと閉じる） |
| `DeviceLocked` | iPhone のロックを解除して再実行 |
| ペアリング検証で失敗 | iPhone のリセットや「位置情報とプライバシーをリセット」で記録が無効になった。初回手順 2・4 をやり直す |
| `usbipd attach` が `Mounting ... within WSL failed` | WSL で `sudo umount /run/usbipd-win` してから再実行 |
| `usbipd attach` が `WSL kernel is not USBIP capable` | usbipd の誤判定。WSL から直接取り込む: `sudo "/mnt/c/Program Files/usbipd-win/WSL/usbip" attach --remote=<Windows ホストの IP> --busid=<BUSID>`（ホストの IP は `ip route` の default via） |

## 注意

- Apple が公開していない仕組み（RemotePairing / CoreDevice）に依存している。iOS のアップデートで動かなくなる可能性がある。
- iOS 18.2 以降は QUIC トンネルが廃止されたため、スクリプトは TCP トンネルを使っている。
- ウィジェット拡張は xtool のバグ（[xtool-org/xtool#313](https://github.com/xtool-org/xtool/issues/313)）で署名・起動に失敗するため、現在 `xtool.yml` で無効化している。

## 参考

- [How to remotely iterate & deploy your sideloaded iOS-apps over tailnet](https://dev.to/kvnpt/how-to-remotely-iterate-deploy-your-sideloaded-ios-apps-over-tailnet-jak)
- [pymobiledevice3: iOS 17+ tunnels](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/ios17-tunnels.md)
