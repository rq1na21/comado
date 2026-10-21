# /// script
# requires-python = ">=3.13"
# dependencies = ["pymobiledevice3==11.40.2"]
# ///
"""USB なしで Tailscale 越しに iPhone へ ipa をインストールする。

iOS 17+ はネットワーク越しの lockdownd (62078) を受け付けないため、RemotePairing (49152) で
トンネルを張り、その中の installation_proxy を使う。root 不要のユーザー空間トンネルで動く。

事前準備 (USB で一度だけ):
    USBMUXD_SOCKET_ADDRESS=/var/run/usbmuxd uvx pymobiledevice3 lockdown remotepairing --pair

使い方:
    xtool dev build --sign --ipa
    uv run scripts/install-over-tailscale.py <iPhone の Tailscale IP> <UDID> xtool/comado.ipa
"""

import asyncio
import sys
from pathlib import Path

import pymobiledevice3.remote.tunnel_service as ts
from pymobiledevice3.remote.common import TunnelProtocol
from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.remote.userspace_tunnel import UserspaceDialPlane
from pymobiledevice3.services.installation_proxy import InstallationProxyService

REMOTE_PAIRING_PORT = 49152


async def main(host: str, udid: str, ipa: Path) -> None:
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
                installer = InstallationProxyService(lockdown=rsd)
                await installer.install_from_local(ipa)
                print("インストール完了")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1], sys.argv[2], Path(sys.argv[3])))
