package version

import (
	"regexp"
	"testing"
)

func TestVersionIsSemver(t *testing.T) {
	if !regexp.MustCompile(`^\d+\.\d+\.\d+$`).MatchString(Version) {
		t.Fatalf("Version %q is not MAJOR.MINOR.PATCH", Version)
	}
}

func TestLineMatchesOtherPorts(t *testing.T) {
	want := "ticketing " + Version + " (go)"
	if got := Line(); got != want {
		t.Fatalf("Line() = %q, want %q", got, want)
	}
}
