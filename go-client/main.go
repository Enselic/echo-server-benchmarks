// tcp_echo_stress.go
//
// Usage:
//   go run tcp_echo_stress.go 200
//   go run tcp_echo_stress.go 127.0.0.1:9001 200

package main

import (
	"io"
	"net"
	"os"
	"strconv"
	"time"
)

func main() {
	if len(os.Args) != 2 && len(os.Args) != 3 {
		os.Stderr.WriteString("usage: tcp_echo_stress [addr] <clients>\n")
		os.Exit(2)
	}

	addr := "192.168.0.104:9001"
	clientsArg := os.Args[1]
	if len(os.Args) == 3 {
		addr = os.Args[1]
		clientsArg = os.Args[2]
	}

	n, err := strconv.Atoi(clientsArg)
	if err != nil || n <= 0 {
		os.Stderr.WriteString("clients must be a positive integer\n")
		os.Exit(2)
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
