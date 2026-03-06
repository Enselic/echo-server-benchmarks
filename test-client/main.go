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
	"sort"
	"sync"
	"time"

	"github.com/alexflint/go-arg"
)

type cliArgs struct {
	Addr              string `arg:"-a,--addr" default:"localhost:80" help:"TCP address host:port"`
	RequestsPerClient uint64 `arg:"-r,--requests-per-client" default:"1" help:"Number of requests each client sends and verifies"`
	ParallelClients   uint64 `arg:"-p,--parallel-clients" default:"1" help:"Number of concurrent clients"`
	// TODO: fix -n
	PayloadRepeatCount uint64 `arg:"-n,--payload-repeat-count" default:"1" help:"Number of times to repeat the 16-byte payload per request (min 1)"`
	Debug              bool   `arg:"-d,--debug" help:"Print a line for each connection attempt"`
}

func dialTCP(addr string, debug bool, clientID uint64) (net.Conn, error) {
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

func makePayloadUnit(clientID uint64, seq uint64) [16]byte {
	var unit [16]byte
	binary.BigEndian.PutUint64(unit[:8], clientID)
	binary.BigEndian.PutUint64(unit[8:], seq)
	return unit
}

func makePayloadBytes(unit [16]byte, repeatCount uint64) []byte {
	totalSize := int(repeatCount) * 16
	buf := make([]byte, totalSize)
	for i := uint64(0); i < repeatCount; i++ {
		copy(buf[i*16:], unit[:])
	}
	return buf
}

func doRequestOnConn(conn net.Conn, clientID uint64, seq uint64, payloadRepeatCount uint64) (time.Duration, error) {
	unit := makePayloadUnit(clientID, seq)
	payloadBytes := makePayloadBytes(unit, payloadRepeatCount)
	totalSize := len(payloadBytes)
	start := time.Now()

	_ = conn.SetDeadline(time.Now().Add(30 * time.Second))

	written := 0
	for written < len(payloadBytes) {
		n, err := conn.Write(payloadBytes[written:])
		if n > 0 {
			written += n
		}
		if err != nil {
			return 0, fmt.Errorf("client %d timed out on %d write: %v", clientID, seq, err)
		}
		if n == 0 {
			return 0, errors.New("short write")
		}
	}
	replyBytes := make([]byte, totalSize)
	if _, err := io.ReadFull(conn, replyBytes); err != nil {
		return 0, fmt.Errorf("client %d timed out on %d read: %v", clientID, seq, err)
	}
	for i := uint64(0); i < payloadRepeatCount; i++ {
		off := i * 16
		gotClient := binary.BigEndian.Uint64(replyBytes[off:])
		gotSeq := binary.BigEndian.Uint64(replyBytes[off+8:])
		if gotClient != clientID || gotSeq != seq {
			return 0, fmt.Errorf("client %d echo mismatch on %d (copy %d): want [%d,%d] got [%d,%d]",
				clientID, seq, i, clientID, seq, gotClient, gotSeq)
		}
	}

	return time.Since(start), nil
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
	latenciesByClient := make(chan []time.Duration, args.ParallelClients)
	worker := func(clientID uint64, toSend uint64) {
		defer wg.Done()

		conn, err := dialTCP(args.Addr, args.Debug, clientID)
		if err != nil {
			os.Stderr.WriteString(fmt.Sprintf("client %d connect failed: %v\n", clientID, err))
			os.Exit(1)
		}
		defer conn.Close()

		localLatencies := make([]time.Duration, 0, toSend)
		for seq := uint64(1); seq <= toSend; seq++ {
			latency, err := doRequestOnConn(conn, clientID, seq, args.PayloadRepeatCount)
			if err != nil {
				os.Stderr.WriteString("request failed: " + err.Error() + "\n")
				os.Exit(1)
			}
			localLatencies = append(localLatencies, latency)
		}

		latenciesByClient <- localLatencies
	}

	// Launch all clients
	for clientID := uint64(0); clientID < args.ParallelClients; clientID++ {
		toSend := args.RequestsPerClient

		wg.Add(1)
		go worker(clientID, toSend)
	}

	// Wait for clients to finish.
	wg.Wait()
	close(latenciesByClient)

	allLatencies := make([]time.Duration, 0, args.ParallelClients*args.RequestsPerClient)
	for clientLatencies := range latenciesByClient {
		allLatencies = append(allLatencies, clientLatencies...)
	}

	p99, err := percentileLatency(allLatencies, 0.99)
	if err != nil {
		os.Stderr.WriteString("failed to compute p99: " + err.Error() + "\n")
		os.Exit(1)
	}
	p999, err := percentileLatency(allLatencies, 0.999)
	if err != nil {
		os.Stderr.WriteString("failed to compute p999: " + err.Error() + "\n")
		os.Exit(1)
	}

	fmt.Printf("requests=%d p99=%s p999=%s\n", len(allLatencies), p99, p999)
}

func percentileLatency(latencies []time.Duration, percentile float64) (time.Duration, error) {
	if len(latencies) == 0 {
		return 0, errors.New("no latencies recorded")
	}
	if percentile <= 0 || percentile > 1 {
		return 0, errors.New("percentile must be in the interval (0, 1]")
	}

	sorted := make([]time.Duration, len(latencies))
	copy(sorted, latencies)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })

	idx := int(percentile*float64(len(sorted))+0.999999999) - 1
	if idx < 0 {
		idx = 0
	}
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}

	return sorted[idx], nil
}

func waitForAddrWithTimeout(addr string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
		if err == nil {
			return conn.Close()
		}
		if time.Now().After(deadline) {
			return err
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func parseArgs() cliArgs {
	var args cliArgs
	parser := arg.MustParse(&args)

	if _, _, err := net.SplitHostPort(args.Addr); err != nil {
		parser.Fail("addr must be in the form host:port. err: " + err.Error())
	}

	return args
}
