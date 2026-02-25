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
	"time"

	"github.com/alexflint/go-arg"
)

type cliArgs struct {
	Addr               string `arg:"--addr" default:"localhost:80" help:"TCP address host:port"`
	NumTotalRequests   uint64 `arg:"--num-total-requests" help:"Total number of requests to send and verify"`
	NumParallelClients uint32 `arg:"--num-parallel-clients" default:"1" help:"Number of concurrent clients"`
}

func main() {
	args := parseArgs()

	// ensure we can connect at all before spawning concurrent clients.
	if err := waitForAddrWithTimeout(args.Addr, 20*time.Second); err != nil {
		os.Stderr.WriteString("failed to connect to " + args.Addr + ": " + err.Error() + "\n")
		os.Exit(1)
	}

	// Any failure is complete failure.
	// Workers must not share mutable state; each worker owns its local state and
	// only reports results back to main.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	errCh := make(chan error, 1)
	resultsCh := make(chan uint64, int(args.NumParallelClients))

	perClient := args.NumTotalRequests / uint64(args.NumParallelClients)
	remainder := args.NumTotalRequests % uint64(args.NumParallelClients)

	var wg sync.WaitGroup
	worker := func(clientID uint32, toSend uint64) {
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
		localConfirmed := uint64(0)

		reportErr := func(err error) {
			select {
			case errCh <- err:
				cancel()
			default:
				// First error wins.
			}
		}

		defer func() {
			resultsCh <- localConfirmed
		}()

		for i := uint64(0); i < toSend; i++ {
			select {
			case <-ctx.Done():
				return
			default:
			}

			if c == nil {
				conn, err := net.DialTimeout("tcp", args.Addr, 20*time.Second)
				if err != nil {
					reportErr(err)
					return
				}
				c = conn
			}

			_ = c.SetDeadline(time.Now().Add(20 * time.Second))

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
			localConfirmed++
		}
	}

	for clientID := uint32(0); clientID < args.NumParallelClients; clientID++ {
		toSend := perClient
		if uint64(clientID) < remainder {
			toSend++
		}
		wg.Add(1)
		go worker(clientID, toSend)
	}

	wg.Wait()
	close(resultsCh)

	select {
	case err := <-errCh:
		os.Stderr.WriteString("request failed: " + err.Error() + "\n")
		os.Exit(1)
	default:
	}

	confirmed := uint64(0)
	for n := range resultsCh {
		confirmed += n
	}
	if confirmed != args.NumTotalRequests {
		os.Stderr.WriteString("incomplete: confirmed " + strconv.FormatUint(confirmed, 10) + " of " + strconv.FormatUint(args.NumTotalRequests, 10) + "\n")
		os.Exit(1)
	}
}

func waitForAddrWithTimeout(addr string, timeout time.Duration) error {
	if conn, err := net.DialTimeout("tcp", addr, timeout); err != nil {
		return err
	} else {
		if err := conn.Close(); err != nil {
			return err
		}
	}
	return nil
}

func parseArgs() cliArgs {
	var args cliArgs
	parser := arg.MustParse(&args)

	if _, _, err := net.SplitHostPort(args.Addr); err != nil {
		parser.Fail("addr must be in the form host:port. err: " + err.Error())
	}
	if args.NumTotalRequests == 0 {
		parser.Fail("--num-total-requests must be > 0")
	}
	if args.NumParallelClients == 0 {
		parser.Fail("--num-parallel-clients must be > 0")
	}

	return args
}
