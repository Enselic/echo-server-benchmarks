package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
)

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
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: %s <port>\n", os.Args[0])
		os.Exit(2)
	}

	addr := ":" + os.Args[1]
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatal(err)
	}
	defer ln.Close()

	// log.Printf("Go TCP echo server listening on %s\n", addr)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConn(conn)
	}
}
