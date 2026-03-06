import * as net from "node:net";

function parsePort(argv: string[]): number {
  if (argv.length !== 3) {
    console.error(`usage: ${argv[1]} <port>`);
    process.exit(2);
  }

  const port = Number(argv[2]);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error("port must be an integer in range 1-65535");
    process.exit(2);
  }

  return port;
}

const port = parsePort(process.argv);

const server = net.createServer((socket) => {
  socket.on("data", (chunk) => {
    if (!socket.write(chunk)) {
      socket.pause();
    }
  });

  socket.on("drain", () => {
    socket.resume();
  });

  socket.on("error", () => {
    socket.destroy();
  });
});

server.on("error", () => {
  process.exit(1);
});

server.listen(port, "0.0.0.0");
