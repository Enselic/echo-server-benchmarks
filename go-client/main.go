// tcp_echo_stress.go
//
// Usage:
//   go run tcp_echo_stress.go 200
//   go run tcp_echo_stress.go --addr 192.168.0.100:9001 200
//   go run tcp_echo_stress.go 192.168.0.100:9001 200

package main

import (
	"io"
	"net"
	"os"
	"strconv"
	"time"

	"github.com/alexflint/go-arg"
)

type cliArgs struct {
	Addr        string   `arg:"--addr" default:"localhost:80" help:"TCP address host:port"`
	Positionals []string `arg:"positional" help:"[addr] <clients>"`
}

func main() {
	var args cliArgs
	parser := arg.MustParse(&args)

	addr := args.Addr
	var clientsArg string
	switch len(args.Positionals) {
	case 1:
		clientsArg = args.Positionals[0]
	case 2:
		addr = args.Positionals[0]
		clientsArg = args.Positionals[1]
	default:
		parser.Fail("usage: tcp_echo_stress [addr] <clients> [--addr host:port]")
	}

	if _, _, err := net.SplitHostPort(addr); err != nil {
		parser.Fail("addr must be in the form host:port")
	}

	n, err := strconv.Atoi(clientsArg)
	if err != nil || n <= 0 {
		parser.Fail("clients must be a positive integer")
	}

	payload := []byte("pingpingpingpingpingpingpingping") // any bytes are fine
	reply := make([]byte, len(payload))

	// Preflight: ensure we can connect at all before spawning concurrent clients.
	if c, err := net.DialTimeout("tcp", addr, 20*time.Second); err != nil {
		os.Stderr.WriteString("failed to connect to " + addr + ": " + err.Error() + "\n")
		os.Exit(1)
	} else {
		_ = c.Close()
	}

	for i := 0; i < n; i++ {
		go func() {
			for {
				c, err := net.Dial("tcp", addr)
				if err != nil {
					os.Stderr.WriteString("failed to connect to " + addr + ": " + err.Error() + "\n")
					os.Exit(1)
					continue
				}
				// Keep this connection busy forever (until server/client dies).
				for {
					if _, err := c.Write(payload); err != nil {
						break
					}
					if _, err := io.ReadFull(c, reply); err != nil {
						break
					}
					// Optional correctness check (kept simple):
					for i := range payload {
						if reply[i] != payload[i] {
							_ = c.Close()
							break
						}
					}
				}
				_ = c.Close()
			}
		}()
	}

	select {} // run until Ctrl+C
}
