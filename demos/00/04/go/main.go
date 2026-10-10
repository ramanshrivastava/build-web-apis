//go:build linux

// Lesson 0.4 demo (Go): neveraccept, a server that listens and never calls accept().
//
// The kernel completes TCP handshakes without the process: a finished
// connection waits in the listener's accept queue until accept() takes it.
// With nobody calling accept(), the queue fills (Linux holds backlog + 1) and
// later clients sit in SYN_SENT. net.Listen cannot show this, because it always
// passes somaxconn as the backlog (maxListenerBacklog() in net/sock_linux.go),
// so every call here is the raw syscall package. Linux only (main_other.go
// says so elsewhere).
//
//	go build -o neveraccept . && ./neveraccept    # backlog 4, 8 clients, hold 30 s for ss
//	./neveraccept --hold 5 --drain                 # then accept everything and close it
//	./neveraccept --smoke                          # assert 5 connected, 3 pending, all 8 drained
package main

import (
	"flag"
	"fmt"
	"os"
	"syscall"
	"time"
	"unsafe"
)

var loopback = [4]byte{127, 0, 0, 1}

func listen(port, backlog int) (int, error) {
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		return -1, os.NewSyscallError("socket", err)
	}
	// TIME_WAIT sockets from a previous --drain still hold the port; allow rebinding.
	if err := syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1); err != nil {
		syscall.Close(fd)
		return -1, os.NewSyscallError("setsockopt", err)
	}
	if err := syscall.Bind(fd, &syscall.SockaddrInet4{Port: port, Addr: loopback}); err != nil {
		syscall.Close(fd)
		return -1, os.NewSyscallError("bind", err)
	}
	// The accept queue's limit, exactly as given (capped by net.core.somaxconn).
	if err := syscall.Listen(fd, backlog); err != nil {
		syscall.Close(fd)
		return -1, os.NewSyscallError("listen", err)
	}
	return fd, nil
}

// startClients opens `count` sockets and starts a non-blocking connect() on each.
func startClients(port, count int) ([]int, error) {
	var clients []int
	for i := 0; i < count; i++ {
		fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0)
		if err != nil {
			return clients, os.NewSyscallError("socket", err)
		}
		clients = append(clients, fd)
		if err := syscall.SetNonblock(fd, true); err != nil {
			return clients, os.NewSyscallError("fcntl", err)
		}
		// connect() returns at once with EINPROGRESS; the handshake goes on in the kernel.
		err = syscall.Connect(fd, &syscall.SockaddrInet4{Port: port, Addr: loopback})
		if err != nil && err != syscall.EINPROGRESS {
			return clients, os.NewSyscallError("connect", err)
		}
	}
	return clients, nil
}

// pollFd is struct pollfd from <poll.h>; the syscall package has no poll wrapper.
type pollFd struct {
	fd      int32
	events  int16
	revents int16
}

const pollOut = 0x4 // POLLOUT

// connected reports whether a non-blocking connect has finished: the socket is
// writable and SO_ERROR is 0. ppoll() with a zero timeout looks without
// waiting; it is the syscall every libc poll() uses on arm64, which has no poll(2).
func connected(fd int) bool {
	pfd := pollFd{fd: int32(fd), events: pollOut}
	var zero syscall.Timespec
	ready, _, errno := syscall.Syscall6(syscall.SYS_PPOLL,
		uintptr(unsafe.Pointer(&pfd)), 1, uintptr(unsafe.Pointer(&zero)), 0, 0, 0)
	if errno != 0 || ready == 0 {
		return false
	}
	soError, err := syscall.GetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_ERROR)
	return err == nil && soError == 0
}

func localPort(fd int) int {
	if sa, err := syscall.Getsockname(fd); err == nil {
		if in4, ok := sa.(*syscall.SockaddrInet4); ok {
			return in4.Port
		}
	}
	return 0
}

func report(clients []int, backlog int) int {
	done := 0
	for i, fd := range clients {
		port := localPort(fd)
		if connected(fd) {
			done++
			fmt.Printf("client %d: connected from port %d (waiting in the accept queue)\n", i+1, port)
		} else {
			fmt.Printf("client %d: pending from port %d (SYN_SENT: no SYN-ACK yet)\n", i+1, port)
		}
	}
	fmt.Printf("result: %d connected, %d pending; the accept queue holds backlog+1 = %d\n",
		done, len(clients)-done, backlog+1)
	return done
}

// drain accepts for up to `limit`, closing each connection server-side first.
func drain(listener, expected int, limit time.Duration) (int, error) {
	if err := syscall.SetNonblock(listener, true); err != nil {
		return 0, os.NewSyscallError("fcntl", err)
	}
	accepted, started := 0, time.Now()
	for accepted < expected {
		elapsed := time.Since(started)
		if elapsed >= limit {
			break
		}
		fd, peer, err := syscall.Accept(listener)
		if err == syscall.EAGAIN {
			time.Sleep(50 * time.Millisecond) // queue empty; a retransmitted SYN may still arrive
			continue
		}
		if err != nil {
			return accepted, os.NewSyscallError("accept", err)
		}
		accepted++
		port := 0
		if in4, ok := peer.(*syscall.SockaddrInet4); ok {
			port = in4.Port
		}
		fmt.Printf("drain: accept() -> fd %d from port %d at +%.1f s\n", fd, port, elapsed.Seconds())
		syscall.Close(fd) // the server closes first, so the server side goes to TIME_WAIT
	}
	fmt.Printf("drain: accepted %d; closed first, so they sit in TIME_WAIT (60 s)\n", accepted)
	return accepted, nil
}

func run(port, backlog, count int, hold float64, doDrain bool) (done, drained int, err error) {
	listener, err := listen(port, backlog)
	if err != nil {
		return 0, 0, err
	}
	defer syscall.Close(listener) // deferred calls run last-in first-out: clients close first
	fmt.Printf("neveraccept: listening on 127.0.0.1:%d, backlog %d; accept() is not called\n", port, backlog)
	clients, err := startClients(port, count)
	defer func() {
		for _, fd := range clients {
			syscall.Close(fd)
		}
	}()
	if err != nil {
		return 0, 0, err
	}
	time.Sleep(500 * time.Millisecond) // let the handshakes that can complete, complete
	done = report(clients, backlog)
	if hold > 0 {
		fmt.Printf("holding %g s: try  ss -lnt 'sport = :%d'\n", hold, port)
		time.Sleep(time.Duration(hold * float64(time.Second)))
	}
	if doDrain {
		drained, err = drain(listener, count, 4*time.Second)
	}
	return done, drained, err
}

func main() {
	port := flag.Int("port", 9004, "port to listen on")
	backlog := flag.Int("backlog", 4, "listen() backlog")
	clients := flag.Int("clients", 8, "connections to attempt")
	hold := flag.Float64("hold", 30, "seconds to wait before exit")
	doDrain := flag.Bool("drain", false, "then accept and close everything")
	smoke := flag.Bool("smoke", false, "assert the Linux queue numbers")
	flag.Parse()
	if !*smoke {
		if _, _, err := run(*port, *backlog, *clients, *hold, *doDrain); err != nil {
			fmt.Println("neveraccept:", err)
			os.Exit(1)
		}
		return
	}
	done, drained, err := run(*port, 4, 8, 0, true)
	if err != nil {
		fmt.Println("neveraccept:", err)
		os.Exit(1)
	}
	if done == 5 && drained == 8 {
		fmt.Println("smoke: OK, 5 waited in the accept queue, 3 were dropped, all 8 drained")
		return
	}
	fmt.Printf("smoke: FAIL, expected 5 connected and 8 drained, got %d and %d\n", done, drained)
	os.Exit(1)
}
