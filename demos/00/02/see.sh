#!/usr/bin/env bash
# demos/00/02/see.sh: routing, ARP, a hand-built DNS query on the wire, TC=1, and NAT as state.
#
#   just see 00/02          # needs network: it asks the lab's real resolver
#
# 1. ip rule + ip route get: which table, interface and source address each destination uses
# 2. ip neigh: the ARP cache; we delete the resolver's entry so the next query must ARP
# 3. tcpdump -X '(arp and host RESOLVER) or udp port 53' while the demo asks for example.com
# 4. strace: a big TXT answer comes back with TC=1 over UDP, then again over TCP
# 5. NAT: a DNAT rule maps 198.51.100.53 (TEST-NET-2, RFC 5737) to the real
#    resolver; conntrack -L shows the translation as a timed table entry. The rule
#    carries a per-invocation comment (see-00-02-<pid>), and cleanup deletes by it.
# 6. dig +trace: the referral chain a recursive resolver walks for us
#
# The DNAT rule is removed on exit. Deleting an ARP entry is harmless: the
# kernel re-learns it on the next packet.
# shellcheck disable=SC2086  # $SUDO ("" or "sudo -n") is split into words on purpose
EXPECT='dst=198\.51\.100\.53 sport=[0-9]+ dport=53 src='
source "$(cd "$(dirname "$0")/../../.." && pwd)/scripts/see/common.sh"
require_tool ip tcpdump strace conntrack iptables python3

demo="$SEE_ROOT/demos/00/02/python/main.py"
cap="$(mktemp)"
resolver="$(awk '$1 == "nameserver" && $2 !~ /:/ {print $2; exit}' /etc/resolv.conf)"
# The comment names this invocation's rule, so cleanup deletes exactly the rule we added,
# never an identical one that was there before.
dnat_rule=(OUTPUT -p udp -d 198.51.100.53 --dport 53 -m comment --comment "see-00-02-$$"
  -j DNAT --to-destination "$resolver:53")
owns_dnat=0 # set only after our "iptables -A" succeeded
cleanup() {
  [ "$owns_dnat" = 1 ] && $SUDO iptables -t nat -D "${dnat_rule[@]}" 2>/dev/null || true
  rm -f "$cap"
  see_cleanup
}
trap cleanup EXIT
see_sh() { see_log "\$ $1"; see_log "$(bash -c "$1" 2>&1)"; }
see_log "# kernel $(uname -r), resolver $resolver (from /etc/resolv.conf)"

see_log "## 1. routing decisions"
see_run ip rule
see_run ip route show match "$resolver"
see_run ip route get "$resolver"
see_run ip route get 1.1.1.1
resolver_dev="$(ip route get "$resolver" | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n 1)"

see_log "## 2. the neighbour (ARP) cache"
see_sh "ip neigh show | grep -v FAILED | head -n 5"

see_log "## 3. one query on the wire (ARP first, if the resolver is on a LAN)"
filter="(arp and host $resolver) or udp port 53"
start_bg $SUDO timeout 5 tcpdump -l -i any -nn -X "$filter" >"$cap" 2>/dev/null
tcpdump_pid=$SEE_BG_PID
sleep 1
if [ "$resolver_dev" != lo ]; then $SUDO ip neigh del "$resolver" dev "$resolver_dev" 2>/dev/null || true; fi
see_run python3 "$demo" example.com
wait_bg "$tcpdump_pid" 10 || true
see_log "\$ tcpdump -i any -nn -X '$filter'"
see_log "$(head -n 20 "$cap")"

see_log "## 4. DNS is UDP until it isn't: TC=1, then TCP"
see_sh "strace -f -s 16 -e trace=socket,connect,sendto,recvfrom python3 $demo --type TXT google.com 2>&1 | grep -E '^(socket|connect|sendto|recvfrom|header|truncated)'"

see_log "## 5. NAT is state: DNAT 198.51.100.53 -> $resolver, then read conntrack"
$SUDO iptables -t nat -A "${dnat_rule[@]}"
owns_dnat=1
see_run $SUDO iptables -t nat -S OUTPUT
see_sh "python3 $demo --server 198.51.100.53 example.com | grep -E '^(dns|sendto|recvfrom|header)'"
see_sh "${SUDO:+$SUDO }conntrack -L -p udp --orig-dst 198.51.100.53 2>&1"

see_log "## 6. the referral chain a resolver walks (dig +trace)"
see_sh "timeout 20 dig +trace example.com | grep -E '^;; Received' | head -n 5"
expect_match
