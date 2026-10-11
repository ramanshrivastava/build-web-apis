#!/usr/bin/env bash
# demos/00/03/see.sh: the receive window closes (win 0), then RTT and loss pace the flow.
#
#   just see 00/03
#
# 1. slowreader (4 KiB SO_RCVBUF, 1 KiB per 100 ms): tcpdump shows "win 0" and
#    window probes; ss -tni shows Send-Q piling up and rwnd_limited near 100%;
#    nstat counts the zero-window advertisements
# 2. the bandwidth-delay product: 20 ms of netem delay each way on port 9003 only,
#    then a fast reader with a fixed 64 KiB buffer vs an autotuned one
# 3. congestion: add 2% loss; ss shows cwnd and ssthresh cut, nstat counts retransmits
#
# netem is attached under a prio qdisc with u32 filters for port 9003, so no
# other loopback traffic is delayed. The script deletes only a qdisc it created:
# if lo already has a root qdisc, the add fails and the script stops untouched.
EXPECT='win 0,'
source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
require_tool tcpdump ss nstat tc python3

demo="$SEE_ROOT/demos/00/03/python/main.py"
cap="$(mktemp)"
owns_qdisc=0 # set only after our "tc qdisc add" succeeded
cleanup() {
  if [ "$owns_qdisc" = 1 ]; then $SUDO tc qdisc del dev lo root 2>/dev/null || true; fi
  rm -f "$cap"
  see_cleanup
}
trap cleanup EXIT
see_sh() { see_log "\$ $1"; see_log "$(bash -c "$1" 2>&1)"; }
sockets="( sport = :9003 or dport = :9003 )"
see_log "# kernel $(uname -r), $(sysctl -n net.ipv4.tcp_congestion_control) congestion control"
see_run sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control \
  net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.rmem_max

see_log "## 1. a slow reader closes the window"
nstat -n # remember the counters now; the next nstat prints the difference
start_bg python3 "$demo" --seconds 5 >"$cap" 2>&1
reader_pid=$SEE_BG_PID
sleep 2
see_sh "timeout 2 tcpdump -l -i lo -nn 'tcp port 9003' 2>/dev/null | head -n 8"
see_run ss -tni "$sockets"
wait_bg "$reader_pid" 15 || true
see_log "\$ python3 $demo --seconds 5"
see_log "$(cat "$cap")"
see_run nstat TcpExtTCPToZeroWindowAdv TcpExtTCPFromZeroWindowAdv TcpExtTCPWinProbe

see_log "## 2. the bandwidth-delay product: 20 ms each way, port 9003 only"
if ! $SUDO tc qdisc add dev lo root handle 1: prio; then
  echo "see: lo already has a root qdisc; not touching it (tc qdisc show dev lo)" >&2
  exit 1
fi
owns_qdisc=1
$SUDO tc qdisc add dev lo parent 1:3 handle 30: netem delay 20ms
$SUDO tc filter add dev lo parent 1:0 protocol ip u32 match ip sport 9003 0xffff flowid 1:3
$SUDO tc filter add dev lo parent 1:0 protocol ip u32 match ip dport 9003 0xffff flowid 1:3
see_run tc qdisc show dev lo
fast=(--read-size 65536 --interval 0 --seconds 3)
see_sh "python3 $demo --rcvbuf 65536 ${fast[*]} | grep -E '^(slowreader: reader|t=2s)'"
see_sh "python3 $demo --rcvbuf 0 ${fast[*]} | grep -E '^(slowreader: reader|t=2s)'"

see_log "## 3. congestion control: 2% loss on top of the delay"
$SUDO tc qdisc change dev lo parent 1:3 handle 30: netem delay 20ms loss 2%
nstat -n
start_bg python3 "$demo" --rcvbuf 0 "${fast[@]}" >"$cap" 2>&1
reader_pid=$SEE_BG_PID
sleep 2.5
see_run ss -tni "sport = :9003"
wait_bg "$reader_pid" 15 || true
see_log "$(grep -E '^t=2s' "$cap")"
see_run nstat TcpRetransSegs TcpExtTCPFastRetrans
expect_match
