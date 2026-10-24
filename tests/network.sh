#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
source "$ROOT_DIR/install-common/lib.sh"
source "$ROOT_DIR/scripts/network-prompt.sh"
fail() { echo "ERROR $*" >&2; exit 1; }
nmcli() {
  case "$*" in
    '-t -f UUID,TYPE,DEVICE connection show --active')
      printf 'wifi-uuid:802-11-wireless:wlan0\n'
      [[ "${multiple:-false}" == true ]] && printf 'cable-uuid:802-3-ethernet:eth0\nvpn-uuid:vpn:tun0\n'
      return 0 ;;
    '-g GENERAL.STATE device show '*) echo '100 (connected)' ;;
    '-e no -g connection.id connection show uuid wifi-uuid') echo 'Casa: principal' ;;
    '-e no -g connection.id connection show uuid cable-uuid') echo 'Rede escritório' ;;
    '-g IP4.ADDRESS device show '*) echo '192.168.1.10/24' ;;
    '-g IP4.GATEWAY device show '*) echo '192.168.1.1' ;;
    '-g IP4.DNS device show '*) echo '9.9.9.9' ;;
    '-g GENERAL.CON-UUID device show wlan0') echo wifi-uuid ;;
    'connection modify uuid '*|'connection up uuid '*) printf '%s\n' "$*" >> "$sandbox/mutations"; return "${modify_exit:-0}" ;;
    *) return 1 ;;
  esac
}
reset_network() { network_interface=''; network_uuid=''; network_address=''; network_gateway=''; network_dns=''; }
reset_network
configure_network_settings < /dev/null
[[ "$network_interface" == wlan0 && "$network_uuid" == wifi-uuid && "$network_address" == 192.168.1.77/24 && "$network_gateway" == 192.168.1.1 && "$network_dns" == 1.1.1.1 ]] || fail 'Personal preset not applied'
[[ ! -f "$sandbox/mutations" ]] || fail 'Discovery modified the network'
multiple=true
reset_network
configure_network_settings < /dev/null
[[ "$network_interface" == eth0 && "$network_uuid" == cable-uuid ]] || fail 'Wired connection not preferred'
reset_network
network_interface=wlan0
configure_network_settings < /dev/null
[[ "$network_interface" == wlan0 && "$network_uuid" == wifi-uuid ]] || fail 'Explicit interface ignored'
# The backend must retain the Wi-Fi profile and credentials by using its UUID.
DRY_RUN=false
STATIC_NETWORK_INTERFACE=wlan0
STATIC_NETWORK_UUID=wifi-uuid
STATIC_NETWORK_ADDRESS=192.168.1.77/24
STATIC_NETWORK_GATEWAY=192.168.1.1
STATIC_NETWORK_DNS=9.9.9.9
sudo() { "$@"; }
run_quiet() { "$@"; }
configure_static_ipv4_network > /dev/null
grep -Fq 'connection modify uuid wifi-uuid' "$sandbox/mutations"
grep -Fq 'connection up uuid wifi-uuid ifname wlan0' "$sandbox/mutations"
! grep -Eq 'connection add|autoconnect no|ipv6' "$sandbox/mutations" || fail 'Unrelated network properties changed'
rm "$sandbox/mutations"
STATIC_NETWORK_UUID=stale-uuid
if configure_static_ipv4_network >/dev/null 2>&1; then fail 'Changed connection accepted'; fi
[[ ! -f "$sandbox/mutations" ]] || fail 'Different network modified'
STATIC_NETWORK_UUID=wifi-uuid
modify_exit=1
if configure_static_ipv4_network >/dev/null 2>&1; then fail 'nmcli failure reported as success'; fi
! grep -q 'connection up' "$sandbox/mutations" || fail 'Connection activated after failed modification'
echo 'Active network selection and static Wi-Fi checks passed'
