// Command ticketing is the Go port of the course's spine app.
//
// One binary, many subcommands. Each module registers its subcommand with one
// line in commands, so modules built in parallel never edit the same line.
// Old subcommands keep working when new ones arrive.
package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/ramanshrivastava/build-web-apis/apps/go/internal/version"
)

// commands is the subcommand registry: one line per module. The same names
// exist in apps/python and apps/rust.
var commands = map[string]func([]string) int{
	"version": cmdVersion,
	// m1: "rawhttp": rawhttp.Main,
	// m2: "api": api.Main,
	// m3: "inventory-grpc": inventory.Main,
	// m4: "worker": worker.Main,
	// m7: "lb": lb.Main,
}

func cmdVersion(_ []string) int {
	fmt.Println(version.Line())
	return 0
}

func usage() string {
	names := make([]string, 0, len(commands))
	for name := range commands {
		names = append(names, name)
	}
	sort.Strings(names)
	var b strings.Builder
	b.WriteString("usage: ticketing <command> [args...]\n\ncommands:\n")
	for _, name := range names {
		b.WriteString("  " + name + "\n")
	}
	return strings.TrimSuffix(b.String(), "\n")
}

// run dispatches to a subcommand. Exit codes: 0 ok, 2 usage error.
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, usage())
		return 2
	}
	name, rest := args[0], args[1:]
	switch name {
	case "-h", "--help", "help":
		fmt.Fprintln(stdout, usage())
		return 0
	}
	cmd, ok := commands[name]
	if !ok {
		fmt.Fprintf(stderr, "ticketing: unknown command %q\n\n%s\n", name, usage())
		return 2
	}
	return cmd(rest)
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
