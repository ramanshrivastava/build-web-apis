//go:build !linux

// The backlog+1 rule is Linux's. This file lets `go build` and `go vet` work
// on macOS, where run.sh re-runs the demo inside the lab instead.
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Println("neveraccept: the backlog+1 rule is Linux's; run it in the lab: just demo 00/04")
	os.Exit(2)
}
