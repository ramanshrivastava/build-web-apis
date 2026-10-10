// Lesson 0.2 demo (Go): a DNS query built by hand and sent over UDP (RFC 1035).
//
// No resolver: the 12-byte header and the question are packed with
// encoding/binary, sent with one WriteTo (sendto), and the answer is parsed
// from the bytes ReadFrom (recvfrom) returns, name compression included. If
// the server sets TC (truncated), the query is repeated over TCP with a 2-byte
// length prefix (RFC 1035 section 4.2.2, RFC 7766): DNS is UDP until it isn't.
//
//	go run main.go example.com               # A record via the resolver in /etc/resolv.conf
//	go run main.go --type TXT google.com     # big answers set TC=1 and fall back to TCP
//	go run main.go --server 1.1.1.1 --tcp example.com
//	go run main.go --smoke                   # needs network; run.sh skips it with CI_OFFLINE=1
package main

import (
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"math/rand/v2"
	"net"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	headerLen = 12 // id, flags, qdcount, ancount, nscount, arcount: six 16-bit fields
	classIN   = 1
	udpLimit  = 512 // RFC 1035 2.3.4: a UDP message without EDNS(0) is at most 512 bytes
)

var (
	types  = map[string]uint16{"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "TXT": 16, "AAAA": 28}
	rcodes = map[int]string{0: "NOERROR", 1: "FORMERR", 2: "SERVFAIL", 3: "NXDOMAIN", 4: "NOTIMP", 5: "REFUSED"}
	// Go slices panic where Python raises IndexError; every read is checked against this.
	errShort = errors.New("message ends early")
)

type header struct{ id, qr, tc, rd, ra, rcode, qd, an int }

func typeName(rtype uint16) string {
	for name, value := range types {
		if value == rtype {
			return name
		}
	}
	return strconv.Itoa(int(rtype))
}

// hexdump returns xxd-style lines: offset, 16 bytes in hex, then the printable ASCII.
func hexdump(data []byte) []string {
	var lines []string
	for offset := 0; offset < len(data); offset += 16 {
		chunk := data[offset:min(offset+16, len(data))]
		hexes := make([]string, len(chunk))
		text := []byte(strings.Repeat(".", len(chunk)))
		for i, b := range chunk {
			hexes[i] = fmt.Sprintf("%02x", b)
			if b >= 32 && b < 127 {
				text[i] = b
			}
		}
		lines = append(lines, fmt.Sprintf("  %04x  %-47s  %s", offset, strings.Join(hexes, " "), text))
	}
	return lines
}

// encodeName turns example.com into 07 'example' 03 'com' 00: length-prefixed labels.
func encodeName(name string) []byte {
	var out []byte
	for _, label := range strings.Split(strings.TrimRight(name, "."), ".") {
		if label == "" { // the root name "." has no labels: it is just the final 00
			continue
		}
		out = append(out, byte(len(label)))
		out = append(out, label...)
	}
	return append(out, 0)
}

func buildQuery(id uint16, name string, qtype uint16) []byte {
	const flags = 0x0100                        // QR=0 (query), OPCODE=0, RD=1: please recurse for me
	q := binary.BigEndian.AppendUint16(nil, id) // network byte order, like struct's "!"
	q = binary.BigEndian.AppendUint16(q, flags)
	q = binary.BigEndian.AppendUint16(q, 1) // one question, nothing else
	q = append(q, 0, 0, 0, 0, 0, 0)         // ancount, nscount, arcount
	q = append(q, encodeName(name)...)
	q = binary.BigEndian.AppendUint16(q, qtype)
	return binary.BigEndian.AppendUint16(q, classIN)
}

// decodeName reads a (possibly compressed) name at offset; it returns the name
// and the offset just after it in the original position.
func decodeName(msg []byte, offset int) (string, int, error) {
	var labels []string
	end, jumps := -1, 0
	for {
		if offset >= len(msg) {
			return "", 0, errShort
		}
		length := int(msg[offset])
		if length&0xc0 == 0xc0 { // pointer: the rest of the name lives elsewhere
			if offset+1 >= len(msg) {
				return "", 0, errShort
			}
			if end < 0 {
				end = offset + 2
			}
			offset = (length&0x3f)<<8 | int(msg[offset+1])
			if jumps++; jumps > 20 {
				return "", 0, errors.New("compression loop")
			}
			continue
		}
		if length == 0 {
			if end < 0 {
				end = offset + 1
			}
			if len(labels) == 0 {
				return ".", end, nil
			}
			return strings.Join(labels, "."), end, nil
		}
		if offset+1+length > len(msg) {
			return "", 0, errShort
		}
		labels = append(labels, string(msg[offset+1:offset+1+length]))
		offset += 1 + length
	}
}

func describeRdata(msg []byte, rtype uint16, start, rdlength int) (string, error) {
	if start+rdlength > len(msg) {
		return "", errShort
	}
	rdata := msg[start : start+rdlength]
	switch {
	case rtype == 1 && rdlength == 4, rtype == 28 && rdlength == 16:
		addr, _ := netip.AddrFromSlice(rdata) // prints like inet_ntop()
		return addr.String(), nil
	case rtype == 2 || rtype == 5:
		name, _, err := decodeName(msg, start)
		return name, err
	case rtype == 16:
		var text []string
		for i := 0; i < len(rdata); i += 1 + int(rdata[i]) {
			piece := rdata[i+1 : min(i+1+int(rdata[i]), len(rdata))]
			text = append(text, strings.ToValidUTF8(string(piece), "�"))
		}
		joined := []rune(strings.Join(text, " ")) // truncate characters, not bytes
		if len(joined) > 60 {
			return `"` + string(joined[:60]) + `"...`, nil
		}
		return `"` + string(joined) + `"`, nil
	}
	return fmt.Sprintf("(%d bytes)", rdlength), nil
}

func parseResponse(msg []byte) (header, []string, error) {
	if len(msg) < headerLen {
		return header{}, nil, errShort
	}
	u16 := func(at int) int { return int(binary.BigEndian.Uint16(msg[at:])) }
	flags := u16(2)
	h := header{
		id: u16(0), qr: flags >> 15, tc: (flags >> 9) & 1, rd: (flags >> 8) & 1,
		ra: (flags >> 7) & 1, rcode: flags & 0xf, qd: u16(4), an: u16(6),
	}
	offset := headerLen
	for i := 0; i < h.qd; i++ { // skip the echoed question
		_, next, err := decodeName(msg, offset)
		if err != nil {
			return h, nil, err
		}
		offset = next + 4 // qtype + qclass
	}
	var answers []string
	for i := 0; i < h.an; i++ {
		name, next, err := decodeName(msg, offset)
		if err != nil {
			return h, nil, err
		}
		if next+10 > len(msg) {
			return h, nil, errShort
		}
		rtype := binary.BigEndian.Uint16(msg[next:]) // then class (2), ttl (4), rdlength (2)
		ttl := binary.BigEndian.Uint32(msg[next+4:])
		rdlength := int(binary.BigEndian.Uint16(msg[next+8:]))
		offset = next + 10
		value, err := describeRdata(msg, rtype, offset, rdlength)
		if err != nil {
			return h, nil, err
		}
		answers = append(answers, fmt.Sprintf("%s %s %s ttl=%d", name, typeName(rtype), value, ttl))
		offset += rdlength
	}
	return h, answers, nil
}

func askUDP(server string, port int, query []byte) ([]byte, error) {
	addr, err := net.ResolveUDPAddr("udp4", net.JoinHostPort(server, strconv.Itoa(port)))
	if err != nil {
		return nil, err
	}
	conn, err := net.ListenPacket("udp4", ":0") // unconnected, like Python's socket
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))
	sent, err := conn.WriteTo(query, addr) // sendto(): one datagram, no connection
	if err != nil {
		return nil, err
	}
	fmt.Printf("sendto() %d bytes -> %s:%d (UDP)\n", sent, server, port)
	reply := make([]byte, 4096)
	n, peer, err := conn.ReadFrom(reply) // recvfrom(): one whole datagram, or nothing
	if err != nil {
		return nil, err
	}
	from := peer.(*net.UDPAddr)
	fmt.Printf("recvfrom() %d bytes <- %s:%d\n", n, from.IP, from.Port)
	return reply[:n], nil
}

func askTCP(server string, port int, query []byte) ([]byte, error) {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(server, strconv.Itoa(port)), 3*time.Second)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))
	framed := binary.BigEndian.AppendUint16(nil, uint16(len(query))) // TCP is a stream: add a length
	framed = append(framed, query...)
	if _, err := conn.Write(framed); err != nil { // Write loops until all is sent, like sendall()
		return nil, err
	}
	fmt.Printf("send() %d bytes -> %s:%d (TCP, 2-byte length + query)\n", len(framed), server, port)
	prefix := make([]byte, 2)
	if _, err := io.ReadFull(conn, prefix); err != nil {
		return nil, closedEarly(err)
	}
	reply := make([]byte, binary.BigEndian.Uint16(prefix))
	if _, err := io.ReadFull(conn, reply); err != nil { // as many reads as it takes
		return nil, closedEarly(err)
	}
	fmt.Printf("recv() %d bytes <- %s:%d (length prefix says %d)\n", 2+len(reply), server, port, len(reply))
	return reply, nil
}

func closedEarly(err error) error {
	if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
		return errors.New("server closed before the full answer arrived")
	}
	return err
}

func systemResolver() string {
	conf, err := os.ReadFile("/etc/resolv.conf")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(conf), "\n") {
		parts := strings.Fields(line)
		if len(parts) >= 2 && parts[0] == "nameserver" && !strings.Contains(parts[1], ":") {
			return parts[1]
		}
	}
	return ""
}

func show(h header, answers []string) {
	rcode, ok := rcodes[h.rcode]
	if !ok {
		rcode = strconv.Itoa(h.rcode)
	}
	fmt.Printf("header: id=0x%04x qr=%d tc=%d rd=%d ra=%d rcode=%s questions=%d answers=%d\n",
		h.id, h.qr, h.tc, h.rd, h.ra, rcode, h.qd, h.an)
	for _, answer := range answers {
		fmt.Println("answer:", answer)
	}
}

func resolve(name, qtype, server string, port int, forceTCP bool) (header, []string, error) {
	id := uint16(rand.Uint32())
	query := buildQuery(id, name, types[qtype])
	fmt.Printf("query: %s %s id=0x%04x, %d bytes\n", name, qtype, id, len(query))
	for _, line := range hexdump(query) {
		fmt.Println(line)
	}
	ask := askUDP
	if forceTCP {
		ask = askTCP
	}
	reply, err := ask(server, port, query)
	if err != nil {
		return header{}, nil, err
	}
	h, answers, err := parseResponse(reply)
	if err != nil {
		return h, nil, err
	}
	if h.id != int(id) {
		return h, nil, fmt.Errorf("reply id 0x%04x does not match query", h.id)
	}
	show(h, answers)
	if h.tc == 1 && !forceTCP {
		fmt.Printf("truncated: the answer did not fit in %d bytes of UDP; retrying over TCP\n", udpLimit)
		if reply, err = askTCP(server, port, query); err != nil {
			return h, nil, err
		}
		if h, answers, err = parseResponse(reply); err != nil {
			return h, nil, err
		}
		show(h, answers)
	}
	return h, answers, nil
}

func fail(err error) int {
	if errors.Is(err, os.ErrDeadlineExceeded) {
		err = errors.New("timed out")
	}
	fmt.Printf("dns: FAIL, %v\n", err)
	return 1
}

func run(name, qtype, server string, port int, forceTCP, smoke bool) int {
	if server == "" {
		server = systemResolver()
	}
	if server == "" {
		fmt.Println("dns: no IPv4 nameserver in /etc/resolv.conf; pass --server IP")
		return 2
	}
	fmt.Printf("dns: resolver %s:%d\n", server, port)
	if !smoke {
		if _, _, err := resolve(name, qtype, server, port, forceTCP); err != nil {
			return fail(err)
		}
		return 0
	}
	udpHeader, udpAnswers, err := resolve("example.com", "A", server, port, false)
	if err != nil {
		return fail(err)
	}
	tcpHeader, tcpAnswers, err := resolve("example.com", "A", server, port, true)
	if err != nil {
		return fail(err)
	}
	found := 0
	for _, answer := range append(udpAnswers, tcpAnswers...) {
		if strings.Contains(answer, " A ") {
			found++
		}
	}
	if udpHeader.rcode == 0 && tcpHeader.rcode == 0 && found > 0 {
		fmt.Printf("smoke: OK, example.com resolved over UDP and TCP (%d A records)\n", found)
		return 0
	}
	fmt.Println("smoke: FAIL, no A record for example.com")
	return 1
}

func main() {
	qtype := flag.String("type", "A", "record type: A, AAAA, CNAME, NS, SOA or TXT")
	server := flag.String("server", "", "resolver IP (default: first in /etc/resolv.conf)")
	port := flag.Int("port", 53, "resolver port")
	forceTCP := flag.Bool("tcp", false, "skip UDP, ask over TCP")
	smoke := flag.Bool("smoke", false, "A for example.com over UDP+TCP")
	flag.Parse()
	// flag stops at the first non-flag argument and argparse does not: take
	// NAME, then parse the flags after it too ("example.com --type TXT").
	name := "example.com"
	if flag.NArg() > 0 {
		name = flag.Arg(0)
		flag.CommandLine.Parse(flag.Args()[1:])
	}
	if _, ok := types[*qtype]; !ok || flag.NArg() > 0 {
		fmt.Fprintln(os.Stderr, "usage: main [--type A|AAAA|CNAME|NS|SOA|TXT] [--server IP] [--port N] [--tcp] [--smoke] [NAME]")
		os.Exit(2)
	}
	os.Exit(run(name, *qtype, *server, *port, *forceTCP, *smoke))
}
