"""VPN surfaces read the provider contract in services/Vpn.qml.

The bar icon and popout used to read Nmcli's NetworkManager-only
vpnActive, and the Network pane drove the raw OpenVPN profile through its
own connect/disconnect pair. Each VPN type now plugs into Vpn.qml, so the
UI must not reach past it to per-type state.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / "Configs/quickshell/aphotic"
VPN = QML / "services/Vpn.qml"
SURFACES = {
    "bar icon": QML / "modules/bar/components/status/VpnStatus.qml",
    "bar popout": QML / "modules/bar/popouts/VpnPopout.qml",
    "network pane": QML / "modules/settings/panes/NetworkPane.qml",
}


def _code(path: Path) -> str:
    return "\n".join(re.sub(r"//.*$", "", line) for line in path.read_text().splitlines())


def _vpn_members() -> set[str]:
    text = _code(VPN)
    props = re.findall(r"property\s+\w+\s+(\w+)\s*:", text)
    props += re.findall(r"property\s+\w+\s+(\w+)\s*$", text, re.M)
    funcs = re.findall(r"function\s+(\w+)\s*\(", text)
    return set(props) | set(funcs)


def test_no_module_reads_per_type_vpn_state():
    for path in (QML / "modules").rglob("*.qml"):
        text = _code(path)
        for token in ("Nmcli.vpnActive", "Nmcli.vpnConnectionName", "Nmcli.getVpnStatus",
                      "Vpn.connectVpn", "Vpn.disconnectVpn"):
            assert token not in text, f"{path.relative_to(ROOT)} still reads {token}"


def test_surfaces_read_the_contract():
    for name, path in SURFACES.items():
        assert re.search(r"\bVpn\.(status|connectionOf|connections|activeConnections)\b",
                         _code(path)), f"{name} does not read Vpn's provider contract"


def test_surfaces_refresh_on_open():
    for name in ("bar popout", "network pane"):
        assert "Vpn.refresh()" in _code(SURFACES[name]), f"{name} does not refresh the list when it opens"


def test_pane_acts_through_the_contract():
    text = _code(SURFACES["network pane"])
    assert 'Vpn.connectProvider("openvpn", "profile")' in text
    assert 'Vpn.disconnectProvider("openvpn", "profile")' in text


def test_surfaces_only_use_members_vpn_defines():
    members = _vpn_members()
    for name, path in SURFACES.items():
        for used in re.findall(r"\bVpn\.(\w+)", _code(path)):
            assert used in members, f"{name} uses Vpn.{used}, which Vpn.qml does not define"


def test_legacy_openvpn_pair_is_gone():
    members = _vpn_members()
    assert "connectVpn" not in members and "disconnectVpn" not in members
