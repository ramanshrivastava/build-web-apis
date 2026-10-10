package main

import (
	"bytes"
	"strings"
	"testing"

	"github.com/ramanshrivastava/build-web-apis/apps/go/internal/version"
)

func TestRegistryHasVersion(t *testing.T) {
	if _, ok := commands["version"]; !ok {
		t.Fatal(`commands has no "version" entry`)
	}
}

func TestHelpListsCommands(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run([]string{"--help"}, &out, &errOut); code != 0 {
		t.Fatalf("exit = %d, want 0", code)
	}
	for name := range commands {
		if !strings.Contains(out.String(), "  "+name) {
			t.Errorf("help does not list %q:\n%s", name, out.String())
		}
	}
}

func TestNoArgsIsUsageError(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run(nil, &out, &errOut); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
	if !strings.Contains(errOut.String(), "usage: ticketing") {
		t.Fatalf("stderr = %q, want usage", errOut.String())
	}
}

func TestUnknownCommandIsUsageError(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run([]string{"nope"}, &out, &errOut); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
	if !strings.Contains(errOut.String(), `unknown command "nope"`) {
		t.Fatalf("stderr = %q", errOut.String())
	}
}

func TestVersionLineShape(t *testing.T) {
	if got, want := version.Line(), "ticketing "+version.Version+" (go)"; got != want {
		t.Fatalf("version.Line() = %q, want %q", got, want)
	}
}
