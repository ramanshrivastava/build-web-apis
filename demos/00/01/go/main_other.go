//go:build !linux

// AF_PACKET exists only on Linux. This file lets `go build` and `go vet` work
// on macOS, where run.sh re-runs the demo inside the lab instead.
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Println("sniff: AF_PACKET is Linux-only; run it in the lab: just demo 00/01 go")
	os.Exit(2)
}
