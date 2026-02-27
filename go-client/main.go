// tcp_echo_stress.go
//
// Usage:
//   go run tcp_echo_stress.go --requests-per-client 1000
//   go run tcp_echo_stress.go --addr 192.168.0.100:9001 --requests-per-client 500 --parallel-clients 200

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
	Addr               string `arg:"-a,--addr" default:"localhost:80" help:"TCP address host:port"`
	RequestsPerClient  uint64 `arg:"-r,--requests-per-client" help:"Number of requests each client sends and verifies"`
	ParallelClients    uint32 `arg:"-p,--parallel-clients" default:"1" help:"Number of concurrent clients"`
	PayloadsPerRequest uint32 `arg:"-n,--payloads-per-request" default:"1" help:"Number of times to repeat the 8-byte payload per request (min 1)"`
	Debug              bool   `arg:"-d,--debug" help:"Print a line for each connection attempt"`
}

func dialTCP(addr string, debug bool, clientID uint32) (net.Conn, error) {
	if debug {
		fmt.Fprintf(os.Stderr, "debug: dialing client=%d addr=%s\n", clientID, addr)
	}
	dialer := net.Dialer{
		Timeout:   120 * time.Second,
		KeepAlive: 30 * time.Second,
	}
	conn, err := dialer.Dial("tcp", addr)
	if err != nil {
		return nil, err
	}
	return conn, nil
}

func doRequestOnConn(conn net.Conn, clientID uint32, seq uint32, payloadsPerRequest uint32) error {
	payloadValue := (uint64(clientID) << 32) | uint64(seq)
	var unit [8]byte
	binary.BigEndian.PutUint64(unit[:], payloadValue)

	totalSize := int(payloadsPerRequest) * 8
	payloadBytes := make([]byte, totalSize)
	for i := uint32(0); i < payloadsPerRequest; i++ {
		copy(payloadBytes[i*8:], unit[:])
	}

	_ = conn.SetDeadline(time.Now().Add(30 * time.Second))

	written := 0
	for written < len(payloadBytes) {
		n, err := conn.Write(payloadBytes[written:])
		if n > 0 {
			written += n
		}
		if err != nil {
			return fmt.Errorf("client %d timed out on %d write: %v", clientID, seq, err)
		}
		if n == 0 {
			return errors.New("short write")
		}
	}
	replyBytes := make([]byte, totalSize)
	if _, err := io.ReadFull(conn, replyBytes); err != nil {
		return fmt.Errorf("client %d timed out on %d read: %v", clientID, seq, err)
	}
	for i := uint32(0); i < payloadsPerRequest; i++ {
		if got := binary.BigEndian.Uint64(replyBytes[i*8:]); got != payloadValue {
			return fmt.Errorf("client %d echo mismatch on %d (copy %d): want %d got %d", clientID, seq, i, payloadValue, got)
		}
	}

	return nil
}

func main() {
	args := parseArgs()

	// TODO: Assume done outside of program?
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

		conn, err := dialTCP(args.Addr, args.Debug, clientID)
		if err != nil {
			os.Stderr.WriteString(fmt.Sprintf("client %d connect failed: %v\n", clientID, err))
			os.Exit(1)
		}
		defer conn.Close()

		for seq := uint32(1); seq <= uint32(toSend); seq++ {
			if err := doRequestOnConn(conn, clientID, seq, args.PayloadsPerRequest); err != nil {
				os.Stderr.WriteString("request failed: " + err.Error() + "\n")
				os.Exit(1)
			}
		}
	}

	// Launch all clients
	for clientID := uint32(0); clientID < args.ParallelClients; clientID++ {
		toSend := args.RequestsPerClient

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
	if args.RequestsPerClient == 0 {
		parser.Fail("--requests-per-client must be > 0")
	}
	if args.ParallelClients == 0 {
		parser.Fail("--parallel-clients must be > 0")
	}
	if args.PayloadsPerRequest < 1 {
		parser.Fail("--payloads-per-request must be >= 1")
	}

	return args
}
