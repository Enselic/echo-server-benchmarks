// tcp_echo_stress.go
//
// Usage:
//   go run tcp_echo_stress.go 200
//
// Edit addr below to point at your echo server.

package main

import (
	"io"
	"net"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) != 2 {
		os.Stderr.WriteString("usage: tcp_echo_stress <clients>\n")
		os.Exit(2)
	}

	n, err := strconv.Atoi(os.Args[1])
	if err != nil || n <= 0 {
		os.Stderr.WriteString("clients must be a positive integer\n")
		os.Exit(2)
	}

	addr := "192.168.0.104:9001" // <-- change me

	payload := []byte("pingpingpingpingpingpingpingping") // any bytes are fine
	reply := make([]byte, len(payload))

	for i := 0; i < n; i++ {
		go func() {
			for {
				c, err := net.Dial("tcp", addr)
				if err != nil {
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
