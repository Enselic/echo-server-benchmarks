// tcp_echo_stress.go
//
// Usage:
//   go run tcp_echo_stress.go --num-total-requests 1000
//   go run tcp_echo_stress.go --addr 192.168.0.100:9001 --num-total-requests 100000 --num-parallel-clients 200

package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"github.com/alexflint/go-arg"
)

type cliArgs struct {
	Addr               string `arg:"--addr" default:"localhost:80" help:"TCP address host:port"`
	NumTotalRequests   uint64 `arg:"--num-total-requests" help:"Total number of requests to send and verify"`
	NumParallelClients uint32 `arg:"--num-parallel-clients" default:"1" help:"Number of concurrent clients"`
}

func doRequest(addr string, clientID uint32, seq uint32) (err error) {
	payloadValue := (uint64(clientID) << 32) | uint64(seq)
	// TODO: Put outside to optimize?
	payloadBytes := make([]byte, 8)
	binary.BigEndian.PutUint64(payloadBytes, payloadValue)

	conn, err := net.DialTimeout("tcp", addr, 20*time.Second)
	if err != nil {
		return err
	}
	defer func() {
		if cerr := conn.Close(); cerr != nil {
			if err != nil {
				err = fmt.Errorf("close failed after error (%v): %w", err, cerr)
				return
			}
			err = fmt.Errorf("close failed: %w", cerr)
		}
	}()

	_ = conn.SetDeadline(time.Now().Add(20 * time.Second))

	written := 0
	for written < len(payloadBytes) {
		n, err := conn.Write(payloadBytes[written:])
		if n > 0 {
			written += n
		}
		if err != nil {
			return err
		}
		if n == 0 {
			return errors.New("short write")
		}
	}
	replyBytes := make([]byte, 8)
	if _, err := io.ReadFull(conn, replyBytes); err != nil {
		return err
	}
	if got := binary.BigEndian.Uint64(replyBytes); got != payloadValue {
		return fmt.Errorf("echo mismatch: want %d got %d", payloadValue, got)
	}

	return nil
}

func main() {
	args := parseArgs()

	// Ensure we can connect at all before spawning concurrent clients.
	if err := waitForAddrWithTimeout(args.Addr, 20*time.Second); err != nil {
		os.Stderr.WriteString("failed to connect to " + args.Addr + ": " + err.Error() + "\n")
		os.Exit(1)
	}

	// This is the code each client will run. Each client will fail the process
	// if it encounters any error.
	var wg sync.WaitGroup
	worker := func(clientID uint32, toSend uint64) {
		defer wg.Done()
		var seq uint32
		fatalFailure := func(err error) {
			os.Stderr.WriteString("request failed: " + err.Error() + "\n")
			os.Exit(1)
		}

		for i := uint64(0); i < toSend; i++ {
			seq++
			if seq == 0 {
				fatalFailure(errors.New("per-client sequence overflow"))
				return
			}
			err := doRequest(args.Addr, clientID, seq)
			if err != nil {
				fatalFailure(err)
				return
			}
		}
	}

	// For improved throughput, we don't want workers to share state, so do some
	// bookkeeping to allow clients to work independently.
	perClient := args.NumTotalRequests / uint64(args.NumParallelClients)
	remainder := args.NumTotalRequests % uint64(args.NumParallelClients)

	// Launch all clients
	for clientID := uint32(0); clientID < args.NumParallelClients; clientID++ {
		toSend := perClient

		// Adjust toSend to get exactly NumTotalRequests across all clients,
		// even when it's not perfectly divisible.
		if uint64(clientID) < remainder {
			toSend++
		}

		wg.Add(1)
		go worker(clientID, toSend)
	}

	// Wait for clients to finish.
	wg.Wait()
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
