// Lesson 0.3 demo (Go): slowreader, a fast sender and a slow reader with a tiny receive buffer.
//
// The sender goroutine writes as fast as conn.Write lets it. The reader asks
// for a tiny SO_RCVBUF *before* connect() (the window scale is fixed in the
// SYN), which net.Dial cannot do on its own: a net.Dialer's Control hook gets
// the raw fd between socket() and connect(). TCP flow control does the rest:
// the reader's buffer fills, it advertises a zero window, the sender's buffer
// fills behind it, and Write parks. Nothing is lost; the flow just stops.
//
//	go run main.go                              # 4 KiB buffer, 1 KiB every 100 ms, 10 s
//	go run main.go --rcvbuf 65536 --read-size 65536 --interval 0   # a fast reader
//	go run main.go --rcvbuf 0 --read-size 65536 --interval 0       # autotuned buffer
//	go run main.go --smoke                      # 3 s, asserts that the sender blocked
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"sync/atomic"
	"syscall"
	"time"
)

var chunk = bytes.Repeat([]byte("x"), 65536) // the sender offers 64 KiB per Write call

// sender accepts one connection and pushes bytes until the peer goes away. The
// reader loop reads its counters from another goroutine, hence the atomics.
type sender struct {
	sent         atomic.Int64 // bytes the kernel accepted into the send buffer
	sendStarted  atomic.Int64 // UnixNano when the current Write began; 0 if none is running
	longestBlock atomic.Int64 // the longest Write call so far, in nanoseconds
}

// blockedFor is how long the current Write call has been waiting (0 if none is).
func (s *sender) blockedFor() time.Duration {
	started := s.sendStarted.Load()
	if started == 0 {
		return 0
	}
	return time.Duration(time.Now().UnixNano() - started)
}

// noteBlock folds a Write duration into longestBlock; both goroutines call it.
func (s *sender) noteBlock(d time.Duration) {
	for {
		old := s.longestBlock.Load()
		if int64(d) <= old || s.longestBlock.CompareAndSwap(old, int64(d)) {
			return
		}
	}
}

func (s *sender) run(listener net.Listener) {
	conn, err := listener.Accept()
	if err != nil {
		return
	}
	defer conn.Close()
	for {
		s.sendStarted.Store(time.Now().UnixNano())
		// Write parks this goroutine while the send buffer is full: the same
		// wait as Python's blocking send(), on a non-blocking fd plus the netpoller.
		n, err := conn.Write(chunk)
		s.noteBlock(s.blockedFor())
		s.sendStarted.Store(0)
		s.sent.Add(int64(n))
		if err != nil {
			return // the reader closed: EPIPE or ECONNRESET
		}
	}
}

func connectReader(port, rcvbuf int) (net.Conn, error) {
	var granted int
	dialer := net.Dialer{
		// Control runs after socket() and before connect(): the SYN carries the
		// window scale chosen from this buffer, and setting it also turns off
		// receive-buffer autotuning for this socket.
		Control: func(network, address string, raw syscall.RawConn) error {
			var opErr error
			err := raw.Control(func(fd uintptr) {
				if rcvbuf > 0 {
					opErr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_RCVBUF, rcvbuf)
				}
				if opErr == nil {
					granted, opErr = syscall.GetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_RCVBUF)
				}
			})
			if err != nil {
				return err
			}
			return opErr
		},
	}
	conn, err := dialer.Dial("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return nil, err
	}
	if rcvbuf > 0 {
		fmt.Printf("slowreader: reader SO_RCVBUF asked %d, kernel set %d\n", rcvbuf, granted)
	} else {
		fmt.Printf("slowreader: reader SO_RCVBUF left to autotuning, starts at %d\n", granted)
	}
	return conn, nil
}

func run(port, rcvbuf, readSize int, interval, seconds float64) (*sender, error) {
	// net.Listen sets SO_REUSEADDR itself. Its backlog is somaxconn rather than
	// Python's 1, which changes nothing for one connection (lesson 0.4 is about backlogs).
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return nil, err
	}
	defer listener.Close()
	fmt.Printf("slowreader: sender listening on 127.0.0.1:%d\n", port)
	s := &sender{}
	go s.run(listener)

	reader, err := connectReader(port, rcvbuf)
	if err != nil {
		return nil, err
	}
	fmt.Printf("slowreader: reading %d bytes every %.3f s for %g s\n", readSize, interval, seconds)
	buf := make([]byte, readSize)
	readTotal, started, nextReport := 0, time.Now(), 1.0
	for {
		elapsed := time.Since(started).Seconds()
		if elapsed >= seconds {
			break
		}
		n, err := reader.Read(buf)
		if err != nil && !errors.Is(err, io.EOF) {
			reader.Close()
			return nil, err
		}
		readTotal += n
		if elapsed >= nextReport {
			sent := int(s.sent.Load())
			// An estimate of the bytes still in kernel buffers: completed Write calls
			// minus bytes read (ss's Send-Q + Recv-Q is the kernel's own, overlapping view).
			inKernel := sent - readTotal
			rate := float64(readTotal) / elapsed / 1024
			blocked := float64(s.blockedFor()) / float64(time.Millisecond)
			fmt.Printf("t=%.0fs sent=%d read=%d in-kernel=%d read-rate=%.1f KiB/s send-blocked=%.0fms\n",
				nextReport, sent, readTotal, inKernel, rate, blocked)
			nextReport += 1.0
		}
		if interval > 0 {
			time.Sleep(time.Duration(interval * float64(time.Second)))
		}
	}
	s.noteBlock(s.blockedFor())
	reader.Close()
	fmt.Printf("summary: sent=%d read=%d longest send() block=%.0f ms\n",
		s.sent.Load(), readTotal, float64(s.longestBlock.Load())/float64(time.Millisecond))
	return s, nil
}

func main() {
	port := flag.Int("port", 9003, "port the sender listens on")
	rcvbuf := flag.Int("rcvbuf", 4096, "reader SO_RCVBUF in bytes (0: autotune)")
	readSize := flag.Int("read-size", 1024, "bytes per read")
	interval := flag.Float64("interval", 0.1, "sleep between reads (s)")
	seconds := flag.Float64("seconds", 10, "how long to read")
	smoke := flag.Bool("smoke", false, "3 s run; assert the sender blocked")
	flag.Parse()
	if !*smoke {
		if _, err := run(*port, *rcvbuf, *readSize, *interval, *seconds); err != nil {
			fmt.Println("slowreader:", err)
			os.Exit(1)
		}
		return
	}
	s, err := run(*port, 4096, 1024, 0.1, 3.0)
	if err != nil {
		fmt.Println("slowreader:", err)
		os.Exit(1)
	}
	if time.Duration(s.longestBlock.Load()) >= 200*time.Millisecond {
		fmt.Println("smoke: OK, the slow reader closed the window and send() blocked")
		return
	}
	fmt.Println("smoke: FAIL, send() never blocked: flow control did not stop the sender")
	os.Exit(1)
}
