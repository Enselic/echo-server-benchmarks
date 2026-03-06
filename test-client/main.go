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
	"github.com/prometheus/client_golang/prometheus"
	dto "github.com/prometheus/client_model/go"
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

	stats, err := buildPrometheusLatencyStats(allLatencies)
	if err != nil {
		os.Stderr.WriteString("failed to compute prometheus latency stats: " + err.Error() + "\n")
		os.Exit(1)
	}

	fmt.Printf("requests=%d avg=%s p50=%s p90=%s p99=%s p999=%s\n",
		stats.SampleCount,
		stats.Average,
		stats.P50,
		stats.P90,
		stats.P99,
		stats.P999,
	)
}

type latencyStats struct {
	SampleCount uint64
	Average     time.Duration
	P50         time.Duration
	P90         time.Duration
	P99         time.Duration
	P999        time.Duration
}

func buildPrometheusLatencyStats(latencies []time.Duration) (latencyStats, error) {
	if len(latencies) == 0 {
		return latencyStats{}, errors.New("no latencies recorded")
	}

	maxLatency := latencies[0]
	for _, latency := range latencies[1:] {
		if latency > maxLatency {
			maxLatency = latency
		}
	}
	bucketCount := int(maxLatency/time.Millisecond) + 1

	histogram := prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    "benchmark_latency_seconds",
		Help:    "Request latency distribution in seconds",
		Buckets: prometheus.LinearBuckets(0.001, 0.001, bucketCount),
	})

	summary := prometheus.NewSummary(prometheus.SummaryOpts{
		Name: "benchmark_latency_summary_seconds",
		Help: "Request latency quantiles in seconds",
		Objectives: map[float64]float64{
			0.50: 0.001,
			0.90: 0.001,
			0.99: 0.001,
			0.999: 0.001,
		},
	})

	for _, latency := range latencies {
		seconds := float64(latency) / float64(time.Second)
		histogram.Observe(seconds)
		summary.Observe(seconds)
	}

	hMetric := &dto.Metric{}
	if err := histogram.Write(hMetric); err != nil {
		return latencyStats{}, fmt.Errorf("write histogram metric: %w", err)
	}
	sMetric := &dto.Metric{}
	if err := summary.Write(sMetric); err != nil {
		return latencyStats{}, fmt.Errorf("write summary metric: %w", err)
	}

	summaryData := sMetric.GetSummary()
	sampleCount := summaryData.GetSampleCount()
	if sampleCount == 0 {
		return latencyStats{}, errors.New("summary has zero samples")
	}

	avg := time.Duration(summaryData.GetSampleSum()/float64(sampleCount) * float64(time.Second))

	quantiles := map[float64]time.Duration{}
	for _, q := range summaryData.GetQuantile() {
		value := time.Duration(q.GetValue() * float64(time.Second))
		quantiles[q.GetQuantile()] = value
	}

	p50, ok := findQuantile(quantiles, 0.50)
	if !ok {
		return latencyStats{}, errors.New("missing p50 quantile")
	}
	p90, ok := findQuantile(quantiles, 0.90)
	if !ok {
		return latencyStats{}, errors.New("missing p90 quantile")
	}
	p99, ok := findQuantile(quantiles, 0.99)
	if !ok {
		return latencyStats{}, errors.New("missing p99 quantile")
	}
	p999, ok := findQuantile(quantiles, 0.999)
	if !ok {
		return latencyStats{}, errors.New("missing p999 quantile")
	}

	return latencyStats{
		SampleCount: sampleCount,
		Average:     avg,
		P50:         p50,
		P90:         p90,
		P99:         p99,
		P999:        p999,
	}, nil
}

func findQuantile(values map[float64]time.Duration, target float64) (time.Duration, bool) {
	const eps = 0.0000001
	for q, value := range values {
		delta := q - target
		if delta < 0 {
			delta = -delta
		}
		if delta <= eps {
			return value, true
		}
	}
	return 0, false
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
