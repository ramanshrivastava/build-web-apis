// Lesson 0.6 demo (Go): the echo server with net.Listen and one goroutine per connection.
//
// No epoll in sight, yet conn.Read is a non-blocking read(2) underneath: on
// EAGAIN, internal/poll parks the goroutine (runtime_pollWait) and the
// runtime's netpoller (runtime/netpoll_epoll.go) wakes it when epoll says the
// fd is readable.
//
// The handler is an explicit Read/Write loop on purpose: io.Copy(conn, conn)
// would take the TCPConn.ReadFrom fast path and move the bytes with splice(),
// hiding the read() -> EAGAIN -> park -> read() sequence the lesson traces.
//
//	go run main.go                   # serve on 127.0.0.1:9006
//	go run main.go --buf-size 4096   # 4 KiB per-connection buffer
//	go run main.go --smoke           # 50 concurrent clients, self-checking
package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"runtime"
	"runtime/pprof"
	"sync"
	"sync/atomic"
	"time"
)

const smokeClients = 50

func handle(conn net.Conn, quiet bool, bufSize int) {
	defer conn.Close()
	port := conn.RemoteAddr().(*net.TCPAddr).Port
	buf := make([]byte, bufSize) // allocated per connection, before the first byte arrives
	echoed := 0
	for {
		n, err := conn.Read(buf) // parks this goroutine until the netpoller says readable
		if n > 0 {
			if _, werr := conn.Write(buf[:n]); werr != nil {
				return
			}
			echoed += n
		}
		if err != nil {
			break // io.EOF: the peer closed
		}
	}
	if !quiet {
		fmt.Printf("port %d: echoed %d bytes, closed\n", port, echoed)
	}
}

func serve(ln net.Listener, quiet bool, bufSize int) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go handle(conn, quiet, bufSize)
	}
}

func listen(port int) net.Listener {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		fmt.Println("echo-goroutines:", err)
		os.Exit(1)
	}
	fmt.Printf("echo-goroutines: pid %d, listening on 127.0.0.1:%d (GOMAXPROCS %d, %d threads)\n",
		os.Getpid(), port, runtime.GOMAXPROCS(0), pprof.Lookup("threadcreate").Count())
	return ln
}

func oneClient(port, number int) bool {
	conn, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return false
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second)) // a stuck server fails the smoke, not the 60 s cap
	message := []byte(fmt.Sprintf("hello from client %d\n", number))
	if _, err := conn.Write(message); err != nil {
		return false
	}
	echoed := make([]byte, len(message))
	if _, err := io.ReadFull(conn, echoed); err != nil {
		return false
	}
	return bytes.Equal(echoed, message)
}

func smoke(port int) int {
	ln := listen(port)
	go serve(ln, true, 65536)
	var wg sync.WaitGroup
	var echoed atomic.Int32 // 50 goroutines count into it at once
	for n := 0; n < smokeClients; n++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			if oneClient(port, n) {
				echoed.Add(1)
			}
		}(n)
	}
	wg.Wait()
	ln.Close()
	ok := int(echoed.Load())
	threads := pprof.Lookup("threadcreate").Count() // OS threads the runtime has created so far
	if ok == smokeClients {
		fmt.Printf("smoke: OK, %d concurrent clients echoed by %d threads\n", ok, threads)
		return 0
	}
	fmt.Printf("smoke: FAIL, %d of %d clients got their echo\n", ok, smokeClients)
	return 1
}

func main() {
	port := flag.Int("port", 9006, "port to listen on")
	bufSize := flag.Int("buf-size", 65536, "bytes per read (the per-connection buffer)")
	smokeFlag := flag.Bool("smoke", false, "50 clients, then exit")
	flag.Parse()
	if *smokeFlag {
		os.Exit(smoke(*port))
	}
	serve(listen(*port), false, *bufSize)
}
