//go:build linux

// Lesson 0.1 demo (Go): an AF_PACKET sniffer that prints each frame's MACs and EtherType.
//
// The same program as python/main.py, on the raw syscall package instead of
// the socket module: syscall.Socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL)),
// syscall.Bind with a SockaddrLinklayer, and syscall.Recvfrom, whose returned
// SockaddrLinklayer carries sll_pkttype. Linux only (main_other.go says so
// elsewhere), and it needs CAP_NET_RAW (root in the lab).
//
//	go build -o sniff . && ./sniff      # 10 frames on lo
//	./sniff --iface eth0 -n 5           # 5 frames on the lab's eth0
//	./sniff --smoke                     # send a UDP datagram on lo and find its frames
package main

import (
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"sort"
	"strings"
	"syscall"
	"time"
)

const (
	ethHeaderLen = 14 // dst MAC, src MAC, EtherType
	smokePort    = 9001
	smokePayload = "m0 smoke"
)

var (
	etherTypes = map[uint16]string{0x0800: "IPv4", 0x0806: "ARP", 0x86dd: "IPv6", 0x8100: "802.1Q"}
	// sll_pkttype, include/uapi/linux/if_packet.h: who the frame was for
	pktTypes = map[uint8]string{0: "host", 1: "broadcast", 2: "multicast", 3: "otherhost", 4: "outgoing"}
	ipProtos = map[byte]string{1: "ICMP", 6: "TCP", 17: "UDP"}
)

// htons puts a 16-bit value in network byte order, which is how the kernel
// reads the AF_PACKET protocol. Go has no socket.htons: write the value
// big-endian, then read the two bytes back in the CPU's own order.
func htons(v uint16) uint16 {
	var b [2]byte
	binary.BigEndian.PutUint16(b[:], v)
	return binary.NativeEndian.Uint16(b[:])
}

func pktName(pkttype uint8) string {
	if name, ok := pktTypes[pkttype]; ok {
		return name
	}
	return fmt.Sprint(pkttype)
}

// strerror capitalises Go's errno text ("no such device") to read like C's strerror(3).
func strerror(err error) string {
	s := err.Error()
	return strings.ToUpper(s[:1]) + s[1:]
}

// describeIPv4 returns a one-line IPv4 summary, plus the UDP/TCP destination port (-1 if none).
func describeIPv4(packet []byte) (string, int) {
	if len(packet) < 20 {
		return "short IPv4 header", -1
	}
	version, ihl := packet[0]>>4, int(packet[0]&0x0f)*4 // ihl: header length in 32-bit words
	if version != 4 || ihl < 20 || len(packet) < ihl {
		return "malformed IPv4 header", -1
	}
	proto := packet[9]
	src, dst := net.IP(packet[12:16]), net.IP(packet[16:20])
	name, ok := ipProtos[proto]
	if !ok {
		name = fmt.Sprintf("proto %d", proto)
	}
	// Fragment offset in bytes: a later fragment carries payload, not the TCP/UDP header.
	offset := int(binary.BigEndian.Uint16(packet[6:8])&0x1fff) * 8
	if offset != 0 {
		return fmt.Sprintf("%s %s > %s fragment at byte %d", name, src, dst, offset), -1
	}
	if (proto == 6 || proto == 17) && len(packet) >= ihl+4 {
		sport := binary.BigEndian.Uint16(packet[ihl:]) // TCP and UDP both start with the ports
		dport := binary.BigEndian.Uint16(packet[ihl+2:])
		return fmt.Sprintf("%s %s:%d > %s:%d", name, src, sport, dst, dport), int(dport)
	}
	return fmt.Sprintf("%s %s > %s", name, src, dst), -1
}

// describe returns the frame's summary line, its EtherType and the transport destination port.
func describe(frame []byte, pkttype uint8) (string, uint16, int) {
	dst, src := net.HardwareAddr(frame[0:6]), net.HardwareAddr(frame[6:12])
	ethertype := binary.BigEndian.Uint16(frame[12:14]) // network byte order on the wire
	name, ok := etherTypes[ethertype]
	if !ok {
		name = "?"
	}
	line := fmt.Sprintf("%s > %s type 0x%04x %s len %d %s",
		src, dst, ethertype, name, len(frame), pktName(pkttype))
	dport := -1
	if ethertype == 0x0800 {
		var summary string
		summary, dport = describeIPv4(frame[ethHeaderLen:])
		line += " | " + summary
	}
	return line, ethertype, dport
}

// openSniffer opens the tap and binds it to one interface.
func openSniffer(iface string) (fd, ifindex int, err error) {
	// SOCK_RAW keeps the link-layer header; htons(ETH_P_ALL) asks for every EtherType.
	fd, err = syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, int(htons(syscall.ETH_P_ALL)))
	if err != nil {
		return -1, 0, err
	}
	ifi, err := net.InterfaceByName(iface)
	if err != nil {
		syscall.Close(fd)
		return -1, 0, syscall.ENODEV // what bind() reports for an unknown interface
	}
	// CPython's bind() tuple takes the protocol in host order and swaps it for
	// you; Go copies SockaddrLinklayer into the sockaddr_ll as is, so htons() again.
	sa := &syscall.SockaddrLinklayer{Protocol: htons(syscall.ETH_P_ALL), Ifindex: ifi.Index}
	if err := syscall.Bind(fd, sa); err != nil {
		syscall.Close(fd)
		return -1, 0, err
	}
	return fd, ifi.Index, nil
}

// sendSmokeDatagrams sends three UDP datagrams to 127.0.0.1:9001 with a receiver
// bound, so the kernel has no reason to answer with ICMP port unreachable.
func sendSmokeDatagrams() (*net.UDPConn, error) {
	target := &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: smokePort}
	receiver, err := net.ListenUDP("udp4", target)
	if err != nil {
		return nil, err
	}
	sender, err := net.ListenUDP("udp4", nil)
	if err != nil {
		receiver.Close()
		return nil, err
	}
	defer sender.Close()
	for i := 0; i < 3; i++ {
		if _, err := sender.WriteToUDP([]byte(smokePayload), target); err != nil {
			receiver.Close()
			return nil, err
		}
	}
	return receiver, nil
}

func sniff(iface string, count int, timeout time.Duration, smoke bool) int {
	fd, ifindex, err := openSniffer(iface)
	if errors.Is(err, syscall.EPERM) || errors.Is(err, syscall.EACCES) {
		fmt.Println("sniff: AF_PACKET needs CAP_NET_RAW; run as root (the lab runs as root)")
		return 3
	}
	if err != nil {
		fmt.Printf("sniff: cannot bind to '%s': %s\n", iface, strerror(err))
		return 2
	}
	defer syscall.Close(fd)
	fmt.Printf("sniff: AF_PACKET socket fd=%d bound to %s (ifindex %d)\n", fd, iface, ifindex)
	if smoke {
		receiver, err := sendSmokeDatagrams()
		if err != nil {
			fmt.Println("sniff: smoke datagrams:", err)
			return 1
		}
		defer receiver.Close()
	}
	// SO_RCVTIMEO: recvfrom() gives up after 0.5 s, so the deadline is honoured
	// even when no frame arrives.
	tv := syscall.NsecToTimeval(int64(500 * time.Millisecond))
	if err := syscall.SetsockoptTimeval(fd, syscall.SOL_SOCKET, syscall.SO_RCVTIMEO, &tv); err != nil {
		fmt.Println("sniff: SO_RCVTIMEO:", strerror(err))
		return 1
	}
	buf := make([]byte, 65535)
	deadline := time.Now().Add(timeout)
	seen, matched := 0, map[string]bool{}
	for seen < count && time.Now().Before(deadline) {
		n, from, err := syscall.Recvfrom(fd, buf, 0)
		if err == syscall.EAGAIN || err == syscall.EINTR {
			continue // the 0.5 s timeout (or a runtime signal): check the deadline again
		}
		if err != nil {
			fmt.Println("sniff: recvfrom:", strerror(err))
			return 1
		}
		ll, ok := from.(*syscall.SockaddrLinklayer) // the sockaddr_ll the kernel filled in
		if !ok || n < ethHeaderLen {
			continue
		}
		seen++
		line, ethertype, dport := describe(buf[:n], ll.Pkttype)
		fmt.Printf("frame %d: %s\n", seen, line)
		if smoke && ethertype == 0x0800 && dport == smokePort {
			matched[pktName(ll.Pkttype)] = true
			if matched["outgoing"] && matched["host"] {
				break
			}
		}
	}
	if !smoke {
		return 0
	}
	if matched["outgoing"] && matched["host"] {
		fmt.Printf("smoke: OK, the datagram to :%d crossed %s twice (outgoing, host)\n", smokePort, iface)
		return 0
	}
	copies := "no"
	if len(matched) > 0 {
		names := make([]string, 0, len(matched))
		for name := range matched {
			names = append(names, name)
		}
		sort.Strings(names)
		copies = fmt.Sprint(names)
	}
	fmt.Printf("smoke: FAIL, saw %s copies of the datagram to :%d\n", copies, smokePort)
	return 1
}

func main() {
	iface := flag.String("iface", "lo", "interface to bind")
	var count int
	flag.IntVar(&count, "n", 10, "frames to print")
	flag.IntVar(&count, "count", 10, "frames to print")
	timeout := flag.Float64("timeout", 10, "give up after N seconds")
	smoke := flag.Bool("smoke", false, "send UDP on lo, expect its frames")
	flag.Parse()
	if *smoke {
		os.Exit(sniff("lo", 50, 5*time.Second, true))
	}
	os.Exit(sniff(*iface, count, time.Duration(*timeout*float64(time.Second)), false))
}
