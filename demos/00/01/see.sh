#!/usr/bin/env bash
# demos/00/01/see.sh: frames, the NIC's counters and rings, and the MTU, seen from the kernel.
#
#   just see 00/01
#
# 1. our AF_PACKET sniffer on lo: one UDP datagram, two frames (outgoing + host)
# 2. tcpdump -e and the sniffer on the default-route NIC (eth0 in the lab): real MACs
# 3. the NIC's counters: ip -s link, ethtool -g/-S, interrupt counts, softnet_stat
# 4. the MTU: the route's MTU, then a dummy NIC shrunk to 1400 and ping -M do
#
# The dummy NIC (m0mtu, 198.51.100.254/24 from TEST-NET-2, RFC 5737) carries no
# real traffic and is deleted on exit.
# shellcheck disable=SC1010  # "ping -M do" is a ping flag, not a loop keyword
EXPECT='message too long, mtu=1400'
source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
require_tool ip ethtool tcpdump ping python3 awk

demo="$SEE_ROOT/demos/00/01/python/main.py"
cap="$(mktemp)"
owns_dummy=0 # set only after our "ip link add" succeeded
cleanup() {
  if [ "$owns_dummy" = 1 ]; then $SUDO ip link del m0mtu 2>/dev/null || true; fi
  rm -f "$cap"
  see_cleanup
}
trap cleanup EXIT
# see_sh 'CMD | FILTER': log the pipeline exactly as typed, then its output.
see_sh() { see_log "\$ $1"; see_log "$(bash -c "$1" 2>&1)"; }

# The NIC and gateway the default route uses (eth0 and 192.168.65.1 in the lab).
route="$(ip route get 1.1.1.1)"
iface="$(sed -n 's/.* dev \([^ ]*\).*/\1/p' <<<"$route" | head -n 1)"
gw="$(sed -n 's/.* via \([^ ]*\).*/\1/p' <<<"$route" | head -n 1)"
see_log "# kernel $(uname -r), default route: dev $iface via $gw"

see_log "## 1. three UDP datagrams on lo: our AF_PACKET socket, then tcpdump"
start_bg $SUDO timeout 4 tcpdump -l -i lo -e -nn udp port 9001 >"$cap" 2>&1
tcpdump_pid=$SEE_BG_PID
sleep 1
see_run $SUDO python3 "$demo" --smoke
wait_bg "$tcpdump_pid" 10 || true
see_log "\$ tcpdump -i lo -e -nn udp port 9001"
see_log "$(grep -v -E '^(tcpdump|listening)' "$cap")"

see_log "## 2. the same view on $iface: tcpdump -e while we ping the gateway"
start_bg $SUDO timeout 5 tcpdump -l -i "$iface" -e -nn -c 4 icmp >"$cap" 2>/dev/null
tcpdump_pid=$SEE_BG_PID
sleep 1
ping -c 2 -i 0.3 -W 1 "$gw" >/dev/null || true
wait_bg "$tcpdump_pid" 10 || true
see_log "\$ tcpdump -i $iface -e -nn -c 4 icmp"
see_log "$(cat "$cap")"
see_run $SUDO python3 "$demo" --iface "$iface" -n 3 --timeout 5

see_log "## 3. the NIC's counters, ring and interrupts"
see_run ip -s link show "$iface"
see_run ethtool -g "$iface"
see_sh "ethtool -S $iface | grep -E 'drop|miss|kicks' | head -n 6"
see_run sysctl net.core.netdev_budget net.core.netdev_budget_usecs net.core.netdev_max_backlog
see_run cat "/sys/class/net/$iface/queues/rx-0/rps_cpus"
# /proc/interrupts is masked inside Docker containers; /sys/kernel/irq has the same counts.
# Each command below is logged exactly as run, so the lesson can print it verbatim.
dev="$(basename "$(readlink -f "/sys/class/net/$iface/device" 2>/dev/null || echo none)")"
if [ -n "$(head -c 1 /proc/interrupts 2>/dev/null)" ]; then
  see_sh "grep -E '$iface|$dev' /proc/interrupts | head -n 4"
else
  see_sh "grep -H -E '^($dev|$iface)' /sys/kernel/irq/*/actions"
  irq_dir="$(grep -l -E "^($dev|$iface)" /sys/kernel/irq/*/actions 2>/dev/null | head -n 1 | xargs -r dirname)"
  if [ -n "$irq_dir" ]; then
    see_sh "cat $irq_dir/per_cpu_count"
    sum_irqs="tr , '\\n' < $irq_dir/per_cpu_count | awk '{s += \$1} END {print s}'"
    see_sh "$sum_irqs"
    stats="/sys/class/net/$iface/statistics"
    see_sh "echo \$(( (\$(cat $stats/rx_packets) + \$(cat $stats/tx_packets)) / \$($sum_irqs) ))"
  fi
fi
see_sh "head -n 2 /proc/net/softnet_stat"
see_sh "head -n 4 /proc/net/softnet_stat | while read -r -a f; do echo \"cpu\$((16#\${f[12]})) processed=\$((16#\${f[0]})) dropped=\$((16#\${f[1]})) time_squeeze=\$((16#\${f[2]}))\"; done"

see_log "## 4. the MTU: the route's limit, then a NIC we shrink ourselves"
see_run ip route get "$gw"
route_mtu="$(ip route get "$gw" | sed -n 's/.*mtu \([0-9]*\).*/\1/p')"
route_mtu="${route_mtu:-$(cat "/sys/class/net/$iface/mtu")}"
see_run ping -M do -s $((route_mtu - 28 + 1)) -c 1 -W 1 "$gw" || true
if ! $SUDO ip link add m0mtu type dummy; then
  echo "see: an interface named m0mtu already exists; not touching it" >&2
  exit 1
fi
owns_dummy=1
$SUDO ip link set m0mtu mtu 1400 up
$SUDO ip addr add 198.51.100.254/24 dev m0mtu
see_run ip -br link show m0mtu
start_bg $SUDO timeout 6 tcpdump -l -i m0mtu -e -nn -c 3 >"$cap" 2>/dev/null
tcpdump_pid=$SEE_BG_PID
sleep 1
see_run ping -M do -s 1373 -c 1 -W 1 198.51.100.1 || true
see_run ping -M do -s 1372 -c 1 -W 1 198.51.100.1 || true
see_run ping -M dont -s 2000 -c 1 -W 1 198.51.100.1 || true
wait_bg "$tcpdump_pid" 10 || true
see_log "\$ tcpdump -i m0mtu -e -nn -c 3"
see_log "$(cat "$cap")"
expect_match
