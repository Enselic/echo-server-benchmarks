package main

import (
	"io"
	"log"
	"net"
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
	ln, err := net.Listen("tcp", ":9002")
	if err != nil {
		log.Fatal(err)
	}
	defer ln.Close()

	log.Println("Go TCP echo server listening on :9002")

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConn(conn)
	}
}
