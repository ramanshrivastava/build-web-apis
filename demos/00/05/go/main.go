//go:build linux

// Lesson 0.5 demo (Go): an echo server two ways, blocking and with raw epoll.
//
// --mode blocking: socket(), bind(), listen(), then accept() and read()/write()
// one client at a time. While it is blocked in read() on client A, client B's
// connection waits in the accept queue: head-of-line blocking.
//
// --mode epoll: every fd is O_NONBLOCK and one epoll instance says which fds
// are ready. read() returns EAGAIN when a socket is drained; that is the signal
// to go back to epoll_wait(), not an error. One goroutine serves every client.
//
// The server never touches the net package: net.Listen would hand its fds to
// the Go runtime's own epoll loop (the netpoller, lesson 0.6). Every call is
// the syscall package on integer fds, and each line printed names the syscall
// just made, so the output lines up with strace. Linux only (main_other.go
// says so elsewhere).
//
//	go build -o echo . && ./echo --mode blocking    # serve on 127.0.0.1:9005
//	./echo --mode epoll
//	./echo --smoke                                  # both modes, two clients each, self-checking
package main

import (
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const backlog = 16

// errnoNames covers the errors this demo can meet: the syscall package has no
// errno-to-name table like Python's errno.errorcode.
var errnoNames = map[syscall.Errno]string{
	syscall.EACCES: "EACCES", syscall.EADDRINUSE: "EADDRINUSE", syscall.EADDRNOTAVAIL: "EADDRNOTAVAIL",
	syscall.EBADF: "EBADF", syscall.ECONNRESET: "ECONNRESET", syscall.EINVAL: "EINVAL",
	syscall.EMFILE: "EMFILE", syscall.ENFILE: "ENFILE", syscall.EPIPE: "EPIPE",
}

// describe formats an error like the Python demo: "EADDRINUSE (Address already in use)".
func describe(err error) string {
	var errno syscall.Errno
	if !errors.As(err, &errno) {
		return err.Error()
	}
	name, ok := errnoNames[errno]
	if !ok {
		name = strconv.Itoa(int(errno))
	}
	text := errno.Error()
	return fmt.Sprintf("%s (%s)", name, strings.ToUpper(text[:1])+text[1:])
}

func port(sa syscall.Sockaddr) int {
	if in4, ok := sa.(*syscall.SockaddrInet4); ok {
		return in4.Port
	}
	return 0
}

func makeListener(listenPort int, nonblocking bool) (int, error) {
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0) // socket()
	if err != nil {
		return -1, os.NewSyscallError("socket", err)
	}
	fail := func(call string, err error) (int, error) {
		syscall.Close(fd)
		return -1, os.NewSyscallError(call, err)
	}
	if err := syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1); err != nil {
		return fail("setsockopt", err)
	}
	if err := syscall.Bind(fd, &syscall.SockaddrInet4{Port: listenPort, Addr: [4]byte{127, 0, 0, 1}}); err != nil {
		return fail("bind", err)
	}
	if err := syscall.Listen(fd, backlog); err != nil {
		return fail("listen", err)
	}
	if nonblocking {
		// O_NONBLOCK with fcntl(F_GETFL) + fcntl(F_SETFL); CPython uses ioctl(FIONBIO).
		if err := syscall.SetNonblock(fd, true); err != nil {
			return fail("fcntl", err)
		}
	}
	return fd, nil
}

func localPort(fd int) int {
	sa, err := syscall.Getsockname(fd)
	if err != nil {
		return 0
	}
	return port(sa)
}

func serveBlocking(lfd, maxClients int) error {
	fmt.Printf("echo-blocking: pid %d, listening fd %d on %d\n", os.Getpid(), lfd, localPort(lfd))
	buf := make([]byte, 65536)
	for served := 0; maxClients == 0 || served < maxClients; served++ {
		fd, peer, err := syscall.Accept4(lfd, syscall.SOCK_CLOEXEC) // blocks until the accept queue is non-empty
		if err != nil {
			return os.NewSyscallError("accept4", err)
		}
		fmt.Printf("accept() = fd %d from port %d\n", fd, port(peer))
		for {
			n, err := syscall.Read(fd, buf) // blocks until bytes arrive or the peer closes
			if err != nil {
				return os.NewSyscallError("read", err)
			}
			fmt.Printf("read(%d) = %d\n", fd, n)
			if n == 0 {
				break
			}
			if _, err := syscall.Write(fd, buf[:n]); err != nil {
				return os.NewSyscallError("write", err)
			}
			fmt.Printf("write(%d) = %d\n", fd, n)
		}
		syscall.Close(fd)
		fmt.Printf("close(%d)\n", fd)
	}
	return nil
}

// watch adds fd to the epoll set for EPOLLIN, level-triggered. Fd is the data
// the kernel hands back with each event, so the loop knows which fd is ready.
func watch(epfd, fd int) error {
	event := syscall.EpollEvent{Events: syscall.EPOLLIN, Fd: int32(fd)}
	return os.NewSyscallError("epoll_ctl", syscall.EpollCtl(epfd, syscall.EPOLL_CTL_ADD, fd, &event))
}

func serveEpoll(lfd, maxClients int) error {
	epfd, err := syscall.EpollCreate1(syscall.EPOLL_CLOEXEC)
	if err != nil {
		return os.NewSyscallError("epoll_create1", err)
	}
	defer syscall.Close(epfd)
	if err := watch(epfd, lfd); err != nil {
		return err
	}
	fmt.Printf("echo-epoll: pid %d, listening fd %d on %d, epoll fd %d\n", os.Getpid(), lfd, localPort(lfd), epfd)
	events := make([]syscall.EpollEvent, 64)
	buf := make([]byte, 65536)
	for served := 0; maxClients == 0 || served < maxClients; {
		n, err := syscall.EpollWait(epfd, events, -1) // sleep until some fd is ready
		if err == syscall.EINTR {
			continue // a signal ended the wait early; nothing is ready
		}
		if err != nil {
			return os.NewSyscallError("epoll_wait", err)
		}
		ready := make([]string, n)
		for i, event := range events[:n] {
			ready[i] = fmt.Sprintf("fd %d", event.Fd)
		}
		fmt.Printf("epoll_wait() = %d ready: %s\n", n, strings.Join(ready, ", "))
		for _, event := range events[:n] {
			fd := int(event.Fd)
			if fd == lfd {
				if err := acceptAll(lfd, epfd); err != nil {
					return err
				}
				continue
			}
			closed, err := echoUntilEagain(fd, buf)
			if err != nil {
				return err
			}
			if closed {
				syscall.EpollCtl(epfd, syscall.EPOLL_CTL_DEL, fd, nil)
				syscall.Close(fd)
				fmt.Printf("close(%d)\n", fd)
				served++
			}
		}
	}
	return nil
}

func acceptAll(lfd, epfd int) error {
	for {
		fd, peer, err := syscall.Accept4(lfd, syscall.SOCK_CLOEXEC)
		if err == syscall.EAGAIN {
			fmt.Println("accept() = EAGAIN (accept queue empty)")
			return nil
		}
		if err == syscall.EMFILE {
			// No fd left: the connection stays queued, the listener stays readable,
			// and level-triggered epoll would wake us again at once. Back off.
			fmt.Println("accept() = EMFILE (no free fd; the connection stays queued)")
			// A raw nanosleep, not time.Sleep: the first Go timer starts the
			// runtime's own netpoller, which needs an epoll fd, and none are left.
			pause := syscall.NsecToTimespec(int64(time.Second))
			syscall.Nanosleep(&pause, nil)
			return nil
		}
		if err != nil {
			return os.NewSyscallError("accept4", err)
		}
		if err := syscall.SetNonblock(fd, true); err != nil {
			return os.NewSyscallError("fcntl", err)
		}
		if err := watch(epfd, fd); err != nil {
			return err
		}
		fmt.Printf("accept() = fd %d from port %d, O_NONBLOCK, added to epoll\n", fd, port(peer))
	}
}

// echoUntilEagain echoes everything readable on fd; it returns true when the peer has closed.
func echoUntilEagain(fd int, buf []byte) (bool, error) {
	for {
		n, err := syscall.Read(fd, buf)
		if err == syscall.EAGAIN {
			fmt.Printf("read(%d) = EAGAIN (drained; back to epoll_wait)\n", fd)
			return false, nil
		}
		if err != nil {
			return false, os.NewSyscallError("read", err)
		}
		fmt.Printf("read(%d) = %d\n", fd, n)
		if n == 0 {
			return true, nil
		}
		// Small echoes fit the send buffer; lesson 1.5 handles EAGAIN here.
		if _, err := syscall.Write(fd, buf[:n]); err != nil {
			return false, os.NewSyscallError("write", err)
		}
		fmt.Printf("write(%d) = %d\n", fd, n)
	}
}

// waitEcho reports whether `message` came back within `timeout`. The smoke
// clients use the net package: they are the test harness, not the lesson.
func waitEcho(client net.Conn, message string, timeout time.Duration) bool {
	client.SetReadDeadline(time.Now().Add(timeout))
	buf := make([]byte, 65536)
	n, err := client.Read(buf)
	return err == nil && string(buf[:n]) == message
}

func echoOnce(client net.Conn, message string, timeout time.Duration) bool {
	if _, err := client.Write([]byte(message)); err != nil {
		return false
	}
	return waitEcho(client, message, timeout)
}

// pyBool prints a bool the way the Python demo does.
func pyBool(b bool) string {
	if b {
		return "True"
	}
	return "False"
}

func smokeMode(mode string, listenPort int) bool {
	lfd, err := makeListener(listenPort, mode == "epoll")
	if err != nil {
		fmt.Println("echo:", describe(err))
		return false
	}
	serve := serveBlocking
	if mode == "epoll" {
		serve = serveEpoll
	}
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		if err := serve(lfd, 2); err != nil {
			fmt.Println("echo:", describe(err))
		}
	}()
	addr := fmt.Sprintf("127.0.0.1:%d", listenPort)
	a, errA := net.Dial("tcp4", addr)
	b, errB := net.Dial("tcp4", addr)
	if errA != nil || errB != nil {
		fmt.Println("echo: smoke clients could not connect:", errors.Join(errA, errB))
		return false
	}
	aOK := echoOnce(a, "hello from A\n", time.Second)
	bEarly := echoOnce(b, "hello from B\n", 500*time.Millisecond) // while A is still connected
	a.Close()
	bLate := bEarly || waitEcho(b, "hello from B\n", time.Second)
	b.Close()
	select {
	case <-finished:
	case <-time.After(2 * time.Second):
	}
	syscall.Close(lfd)
	time.Sleep(100 * time.Millisecond)
	if mode == "blocking" {
		ok := aOK && !bEarly && bLate
		fmt.Printf("smoke: blocking: B echoed only after A hung up: %s\n", pyBool(ok))
		return ok
	}
	ok := aOK && bEarly
	fmt.Printf("smoke: epoll: B echoed while A was still connected: %s\n", pyBool(ok))
	return ok
}

func main() {
	mode := flag.String("mode", "epoll", "blocking or epoll")
	listenPort := flag.Int("port", 9005, "port to listen on")
	maxClients := flag.Int("max-clients", 0, "exit after N clients (0: forever)")
	smoke := flag.Bool("smoke", false, "test both modes and exit")
	flag.Parse()
	if *mode != "blocking" && *mode != "epoll" {
		fmt.Fprintln(os.Stderr, "echo: --mode must be blocking or epoll")
		os.Exit(2)
	}
	if *smoke {
		blocking, epoll := smokeMode("blocking", *listenPort), smokeMode("epoll", *listenPort)
		if blocking && epoll {
			fmt.Println("smoke: OK")
			return
		}
		fmt.Println("smoke: FAIL")
		os.Exit(1)
	}
	lfd, err := makeListener(*listenPort, *mode == "epoll")
	if err == nil && *mode == "blocking" {
		err = serveBlocking(lfd, *maxClients)
	} else if err == nil {
		err = serveEpoll(lfd, *maxClients)
	}
	if err != nil {
		fmt.Println("echo:", describe(err))
		os.Exit(1)
	}
}
