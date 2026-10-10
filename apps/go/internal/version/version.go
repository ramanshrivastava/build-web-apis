// Package version holds the app version shared by the Python, Go and Rust ports.
package version

// Version is the ticketing app version. Keep it equal to apps/python and apps/rust.
const Version = "0.0.0"

// Line returns what `ticketing version` prints; every port prints the same shape.
func Line() string {
	return "ticketing " + Version + " (go)"
}
