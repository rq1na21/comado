# /// script
# requires-python = ">=3.13"
# dependencies = ["pymobiledevice3==11.40.2"]
# ///
"""USB なしで Tailscale 越しに iPhone を操作する（インストール・スクリーンショット）。

iOS 17+ はネットワーク越しの lockdownd (62078) を受け付けないため、RemotePairing (49152) で
トンネルを張り、その中のサービスを使う。root 不要のユーザー空間トンネルで動く。

事前準備 (USB で一度だけ):
    USBMUXD_SOCKET_ADDRESS=/var/run/usbmuxd uvx pymobiledevice3 lockdown remotepairing --pair

使い方:
    xtool dev build --sign --ipa
    uv run scripts/tailscale-device.py <iPhone の Tailscale IP> <UDID> install xtool/comado.ipa
    uv run scripts/tailscale-device.py <iPhone の Tailscale IP> <UDID> screenshot out.png
    uv run scripts/tailscale-device.py <iPhone の Tailscale IP> <UDID> crashes <保存先ディレクトリ>
"""

import asyncio
import sys
from contextlib import suppress
from pathlib import Path

from pymobiledevice3.exceptions import AlreadyMountedError
import pymobiledevice3.remote.tunnel_service as ts
from pymobiledevice3.remote.common import TunnelProtocol
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.remote.userspace_tunnel import UserspaceDialPlane
from pymobiledevice3.services.crash_reports import CrashReportsManager
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.mobile_image_mounter import auto_mount

REMOTE_PAIRING_PORT = 49152


async def install(rsd: RemoteServiceDiscoveryService, ipa: Path) -> None:
    await InstallationProxyService(lockdown=rsd).install_from_local(ipa)
    print("インストール完了")


async def screenshot(rsd: RemoteServiceDiscoveryService, out: Path) -> None:
    # 画面取得は開発者サービス。初回は Developer Disk Image のダウンロードとマウントが走る
    with suppress(AlreadyMountedError):
        await auto_mount(rsd)
    async with DvtProvider(rsd) as dvt, Screenshot(dvt) as shot:
        out.write_bytes(await shot.get_screenshot())
    print(f"保存: {out}")


async def crashes(rsd: RemoteServiceDiscoveryService, out: Path) -> None:
    """comado 関連のクラッシュログを取得する"""
    out.mkdir(parents=True, exist_ok=True)
    async with CrashReportsManager(rsd) as manager:
        await manager.pull(str(out), match=r"(?i)comado", progress_bar=False)
    print(f"保存: {out}")


async def main(host: str, udid: str, command: str, path: Path) -> None:
    ts.USE_USERSPACE_TUNNEL = True
    service = await ts.create_core_device_tunnel_service_using_remotepairing(udid, host, REMOTE_PAIRING_PORT)
    # iOS 18.2+ は QUIC トンネルを廃止したので TCP
    async with ts.start_tunnel_over_remotepairing(service, protocol=TunnelProtocol.TCP) as tunnel:
        tun = tunnel.client.tun
        tun.set_peer(tunnel.address)
        async with UserspaceDialPlane(tun, tunnel.address) as dial_plane:
            async with RemoteServiceDiscoveryService(
                (tunnel.address, tunnel.port), open_connection=dial_plane.dial
            ) as rsd:
                print(f"接続: {rsd.product_type} iOS {rsd.product_version}")
                await {"install": install, "screenshot": screenshot, "crashes": crashes}[command](rsd, path)


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[3] not in ("install", "screenshot", "crashes"):
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1], sys.argv[2], sys.argv[3], Path(sys.argv[4])))
