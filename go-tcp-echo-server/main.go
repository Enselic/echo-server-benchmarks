package main

import (
	"io"
	"log"
	"net"
	"strconv"

	"github.com/alexflint/go-arg"
)

type cliArgs struct {
	Port        int      `arg:"-p,--port" help:"TCP port to listen on"`
	Positionals []string `arg:"positional" help:"<port>"`
}

func handleConn(c net.Conn) {
	defer c.Close()

	buf := make([]byte, 32*1024) // 32 KB buffer
	for {
		n, err := c.Read(buf)
		if n > 0 {
			_, werr := c.Write(buf[:n])
			if werr != nil {
				return
			}
		}
		if err != nil {
			if err != io.EOF {
				// optional: log unexpected errors
			}
			return
		}
	}
}

func main() {
	var args cliArgs
	parser := arg.MustParse(&args)

	port := args.Port
	if port == 0 {
		if len(args.Positionals) != 1 {
			parser.Fail("usage: go-tcp-echo-server [-p port] <port>")
		}
		p, err := strconv.Atoi(args.Positionals[0])
		if err != nil {
			parser.Fail("port must be an integer")
		}
		port = p
	}
	if port <= 0 || port > 65535 {
		parser.Fail("port must be between 1 and 65535")
	}

	addr := ":" + strconv.Itoa(port)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatal(err)
	}
	defer ln.Close()

	log.Printf("Go TCP echo server listening on %s\n", addr)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConn(conn)
	}
}
