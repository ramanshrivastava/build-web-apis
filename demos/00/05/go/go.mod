// A module of its own, so `go build .` and `go vet .` honour the build tags:
// main.go is Linux-only, main_other.go is what other platforms get.
module demo-00-05

go 1.23
