// tcp_echo_stress.go
//
// Usage:
//   go run tcp_echo_stress.go --num-total-requests 1000
//   go run tcp_echo_stress.go --addr 192.168.0.100:9001 --num-total-requests 100000 --num-parallel-clients 200

package main

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/alexflint/go-arg"
)

type cliArgs struct {
	Addr               string `arg:"--addr" default:"localhost:80" help:"TCP address host:port"`
	NumTotalRequests   uint64 `arg:"--num-total-requests" help:"Total number of requests to send and verify"`
	NumParallelClients int    `arg:"--num-parallel-clients" default:"1" help:"Number of concurrent clients"`
}

func main() {
	var args cliArgs
	parser := arg.MustParse(&args)

	if _, _, err := net.SplitHostPort(args.Addr); err != nil {
		parser.Fail("addr must be in the form host:port")
	}
	if args.NumTotalRequests == 0 {
		parser.Fail("--num-total-requests must be > 0")
	}
	if args.NumParallelClients <= 0 {
		parser.Fail("--num-parallel-clients must be > 0")
	}
	if uint64(args.NumParallelClients) > uint64(^uint32(0)) {
		parser.Fail("--num-parallel-clients too large")
	}

	// Preflight: ensure we can connect at all before spawning concurrent clients.
	if c, err := net.DialTimeout("tcp", args.Addr, 20*time.Second); err != nil {
		os.Stderr.WriteString("failed to connect to " + args.Addr + ": " + err.Error() + "\n")
		os.Exit(1)
	} else {
		_ = c.Close()
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var firstErr atomic.Value // stores error
	var errOnce sync.Once
	var nextRequest atomic.Uint64
	var confirmed atomic.Uint64

	var wg sync.WaitGroup
	worker := func(clientID uint32) {
		defer wg.Done()

		var payload [8]byte
		reply := make([]byte, len(payload))
		var c net.Conn
		var seq uint32
		defer func() {
			if c != nil {
				_ = c.Close()
			}
		}()

		reportErr := func(err error) {
			errOnce.Do(func() {
				firstErr.Store(err)
				cancel()
			})
		}

		for {
			select {
			case <-ctx.Done():
				return
			default:
			}

			id := nextRequest.Add(1)
			if id > args.NumTotalRequests {
				return
			}

			if c == nil {
				conn, err := net.DialTimeout("tcp", args.Addr, 20*time.Second)
				if err != nil {
					reportErr(err)
					return
				}
				c = conn
			}

			seq++
			if seq == 0 {
				reportErr(errors.New("per-client sequence overflow"))
				return
			}
			v := (uint64(clientID) << 32) | uint64(seq)
			binary.BigEndian.PutUint64(payload[:], v)

			written := 0
			for written < len(payload) {
				n, err := c.Write(payload[written:])
				if n > 0 {
					written += n
				}
				if err != nil {
					_ = c.Close()
					c = nil
					reportErr(err)
					return
				}
				if n == 0 {
					_ = c.Close()
					c = nil
					reportErr(errors.New("short write"))
					return
				}
			}
			if _, err := io.ReadFull(c, reply); err != nil {
				_ = c.Close()
				c = nil
				reportErr(err)
				return
			}
			if got := binary.BigEndian.Uint64(reply); got != v {
				reportErr(fmt.Errorf("echo mismatch: want %d got %d", v, got))
				return
			}

			confirmed.Add(1)
		}
	}

	for i := 0; i < args.NumParallelClients; i++ {
		wg.Add(1)
		go worker(uint32(i))
	}

	wg.Wait()
	if v := firstErr.Load(); v != nil {
		err := v.(error)
		os.Stderr.WriteString("request failed: " + err.Error() + "\n")
		os.Exit(1)
	}

	if confirmed.Load() != args.NumTotalRequests {
		os.Stderr.WriteString("incomplete: confirmed " + strconv.FormatUint(confirmed.Load(), 10) + " of " + strconv.FormatUint(args.NumTotalRequests, 10) + "\n")
		os.Exit(1)
	}
}
