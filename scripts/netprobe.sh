#!/bin/bash
# netprobe.sh — read-only network probe for the Mac mini cluster.
# Changes NO settings, reads NO keychain items, sends NO API keys, makes NO model calls.
# Usage:
#   bash netprobe.sh snapshot            # T0: local network state (safe during the research run)
#   bash netprobe.sh egress              # T1: internet reachability and latency (tiny traffic)
#   bash netprobe.sh peer IP [IP ...]    # T2: node-to-node reachability
# Optional: PROBE_EXTRA_URLS="https://a.example https://b.example" adds extra egress checks.
# Output: key=value lines on stdout. Save with:  bash netprobe.sh egress | tee "netprobe-$(hostname -s)-egress-$(date +%Y%m%dT%H%M%S).txt"
set -u
mode="${1:-snapshot}"; shift || true
now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
kv() { printf '%s=%s\n' "$1" "$2"; }
kv probe_mode "$mode"; kv observed_at "$(now)"; kv host "$(hostname -s)"; kv macos "$(sw_vers -productVersion)"

snapshot() {
  # Hardware ports -> device names and MAC addresses (MACs are needed for school IP registration).
  networksetup -listallhardwareports | awk '
    /^Hardware Port:/ {sub(/^Hardware Port: /,""); port=$0}
    /^Device:/ {dev=$2}
    /^Ethernet Address:/ {print "hwport=" port " | dev=" dev " | mac=" $3}'
  echo "--- service_order"; networksetup -listnetworkserviceorder | grep -E '^\([0-9*]+\)'
  def_if=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  kv default_route_interface "${def_if:-none}"
  kv default_gateway "$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')"
  for dev in $(networksetup -listallhardwareports | awk '/^Device:/{print $2}'); do
    ip=$(ipconfig getifaddr "$dev" 2>/dev/null) || continue
    [ -n "$ip" ] || continue
    kv "if_${dev}_ip" "$ip"
    kv "if_${dev}_mask" "$(ipconfig getoption "$dev" subnet_mask 2>/dev/null)"
    kv "if_${dev}_router" "$(ipconfig getoption "$dev" router 2>/dev/null)"
    kv "if_${dev}_media" "$(ifconfig "$dev" 2>/dev/null | awk '/media:/{$1="";print}' | xargs)"
    kv "if_${dev}_mtu" "$(ifconfig "$dev" 2>/dev/null | awk '/mtu/{for(i=1;i<=NF;i++) if($i=="mtu") print $(i+1)}' | head -1)"
    kv "if_${dev}_dhcp_server" "$(ipconfig getoption "$dev" server_identifier 2>/dev/null)"
  done
  kv dns_servers "$(scutil --dns | awk '/nameserver\[/{print $3}' | sort -u | xargs)"
  kv system_proxy "$(scutil --proxy | grep -E 'HTTPSEnable|HTTPSProxy|ProxyAutoConfigEnable' | xargs)"
  kv env_proxy "${HTTPS_PROXY:-${https_proxy:-none}}"
  # 802.1X profile presence (names only).
  kv dot1x_profiles "$(profiles list 2>/dev/null | grep -ci 8021x || echo 0)"
  kv firewall "$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | xargs)"
}

curlt() { # url label — mimic research transport: no proxy
  local out
  out=$(curl -sS -o /dev/null --noproxy '*' --max-time 15 \
    -w '%{http_code} dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} total=%{time_total} ip=%{remote_ip}' "$1" 2>&1)
  kv "egress_$2" "$out"
}

egress() {
  # Captive portal check: Apple's endpoint returns the word Success when the path is open.
  kv captive_portal "$(curl -sS --noproxy '*' --max-time 10 http://captive.apple.com/hotspot-detect.html 2>&1 | grep -q Success && echo none || echo SUSPECTED)"
  kv dns_huggingface "$(dscacheutil -q host -a name huggingface.co | awk '/ip_address/{print $2}' | xargs)"
  # No credentials are sent: any HTTP status (even 401/403/404) means the path is OPEN; 000 means blocked/timeout.
  curlt https://github.com github
  curlt https://huggingface.co huggingface
  curlt https://pypi.org/simple/ pypi
  curlt https://formulae.brew.sh brew
  n=0; for u in ${PROBE_EXTRA_URLS:-}; do n=$((n+1)); curlt "$u" "extra$n"; done
  # Latency distribution to Hugging Face (TLS handshake only, 20 samples, no credentials).
  samples=""
  for i in $(seq 1 20); do
    t=$(curl -sS -o /dev/null --noproxy '*' --max-time 15 -w '%{time_appconnect}' https://huggingface.co 2>/dev/null || echo fail)
    samples="$samples $t"
  done
  kv huggingface_tls_seconds_x20 "$(echo $samples)"
  kv huggingface_tls_failures "$(echo $samples | tr ' ' '\n' | grep -c -E 'fail|^0\.000000$')"
  # Path MTU sanity toward gateway (1472 payload + 28 = 1500).
  gw=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
  [ -n "$gw" ] && kv mtu1500_to_gateway "$(ping -c 2 -D -s 1472 -t 5 "$gw" >/dev/null 2>&1 && echo pass || echo FAIL)"
}

peer() {
  [ $# -gt 0 ] || { echo "usage: netprobe.sh peer IP [IP ...]"; exit 2; }
  for p in "$@"; do
    loss=$(ping -c 10 -i 0.2 -t 10 "$p" 2>/dev/null | awk -F', ' '/packet loss/{print $3}')
    rtt=$(ping -c 10 -i 0.2 -t 10 "$p" 2>/dev/null | awk -F'= ' '/round-trip/{print $2}')
    kv "peer_${p}_ping" "loss=${loss:-unreachable} rtt=${rtt:-na}"
    kv "peer_${p}_ssh22" "$(nc -z -G 3 "$p" 22 >/dev/null 2>&1 && echo open || echo closed)"
    kv "peer_${p}_hops" "$(traceroute -n -m 4 -q 1 -w 2 "$p" 2>/dev/null | tail -n +1 | wc -l | xargs)"
  done
  # mDNS: does <name>.local resolve on this network? (school networks often block multicast)
  tmp=$(mktemp); dns-sd -B _ssh._tcp local. >"$tmp" 2>/dev/null & pid=$!; sleep 4; kill "$pid" 2>/dev/null
  kv mdns_ssh_hosts_seen "$(awk '/Add/{print $NF}' "$tmp" | sort -u | xargs)"; rm -f "$tmp"
  kv mdns_note "empty list = multicast likely blocked; use IPs in hostfiles instead of .local"
}

case "$mode" in
  snapshot) snapshot ;;
  egress) egress ;;
  peer) peer "$@" ;;
  *) echo "unknown mode: $mode"; exit 2 ;;
esac
