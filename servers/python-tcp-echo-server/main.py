#!/usr/bin/env python3
import asyncio
import sys


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            data = await reader.read(32 * 1024)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()


def parse_port(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {sys.argv[0]} <port>", file=sys.stderr)
        raise SystemExit(2)

    try:
        port = int(argv[1])
    except ValueError:
        print("port must be an integer", file=sys.stderr)
        raise SystemExit(2)

    if port < 1 or port > 65535:
        print("port must be in range 1-65535", file=sys.stderr)
        raise SystemExit(2)

    return port


async def main() -> None:
    port = parse_port(sys.argv)
    server = await asyncio.start_server(handle_client, host="0.0.0.0", port=port)

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
