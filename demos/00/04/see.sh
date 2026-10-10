#!/usr/bin/env bash
# demos/00/04/see.sh: the accept queue fills, the SYN queue is a different queue, TIME_WAIT is a timer.
#
#   just see 00/04
#
# 1. the limits: somaxconn, tcp_max_syn_backlog, syncookies
# 2. neveraccept (backlog 4, 8 clients): ss -lnt shows Recv-Q 5 / Send-Q 4, ss
#    shows 3 clients in SYN-SENT, ss -tm shows the queued connections already own
#    socket buffers, tcpdump shows the dropped SYNs retransmitted, /proc/net/tcp
#    shows the raw states, nstat counts ListenOverflows
# 3. the other queue: drop the server's SYN-ACKs with iptables, so handshakes stay
#    half-open; ss shows SYN-RECV entries while the accept queue stays empty
# 4. --drain: accept and close server-side first; ss -o shows TIME-WAIT timers
#
# The iptables rule matches only SYN-ACKs from port 9004 and is removed on exit.
EXPECT='^LISTEN +5 +4 '
source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
require_tool ss nstat tcpdump iptables python3

demo="$SEE_ROOT/demos/00/04/python/main.py"
cap="$(mktemp)"
drop_synack=(INPUT -p tcp --sport 9004 --tcp-flags "SYN,ACK" "SYN,ACK" -j DROP)
cleanup() {
  $SUDO iptables -D "${drop_synack[@]}" 2>/dev/null || true
  rm -f "$cap"
  see_cleanup
}
trap cleanup EXIT
see_sh() { see_log "\$ $1"; see_log "$(bash -c "$1" 2>&1)"; }
see_log "# kernel $(uname -r)"

see_log "## 1. the limits"
see_run sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_syncookies \
  net.ipv4.tcp_syn_linear_timeouts net.ipv4.tcp_abort_on_overflow \
  net.ipv4.ip_local_port_range net.ipv4.tcp_tw_reuse net.ipv4.tcp_max_tw_buckets

see_log "## 2. listen(4), never accept(), 8 clients"
nstat -n
$SUDO timeout 4 tcpdump -l -i lo -nn 'tcp dst port 9004 and tcp[tcpflags] == tcp-syn' >"$cap" 2>/dev/null &
tcpdump_pid=$!
sleep 0.5
start_bg python3 "$demo" --hold 4
sleep 1.5
see_run ss -lnt 'sport = :9004'
see_run ss -tn state syn-sent 'dport = :9004'
see_sh "ss -tmn state established 'sport = :9004' | head -n 5"
see_sh "head -n 1 /proc/net/tcp; grep -i ':232C ' /proc/net/tcp | head -n 4"
wait "$tcpdump_pid" || true
see_log "\$ tcpdump -i lo -nn 'tcp dst port 9004 and tcp[tcpflags] == tcp-syn'"
see_log "$(cat "$cap")"
see_run nstat TcpExtListenOverflows TcpExtListenDrops
sleep 2 # let neveraccept exit

see_log "## 3. the SYN queue: SYN-ACKs dropped, handshakes stay half-open"
$SUDO iptables -I "${drop_synack[@]}"
start_bg python3 "$demo" --clients 3 --hold 3
sleep 1.5
see_run ss -lnt 'sport = :9004'
see_run ss -tn state syn-recv 'sport = :9004'
sleep 2.5
$SUDO iptables -D "${drop_synack[@]}"

see_log "## 4. drain: accept, close server-side first, TIME_WAIT"
see_sh "python3 $demo --hold 0 --drain | grep -E '^(result|drain)'"
see_sh "ss -tano state time-wait 'sport = :9004' | head -n 4"
expect_match
