using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

if (args.Length != 1 || !int.TryParse(args[0], out var port) || port < 1 || port > 65535)
{
    Console.Error.WriteLine("usage: csharp-echo-server <port>");
    Environment.Exit(2);
}

var listener = new TcpListener(IPAddress.Any, port);
listener.Start();

while (true)
{
    var client = await listener.AcceptTcpClientAsync();
    _ = Task.Run(() => HandleClient(client));
}

static async Task HandleClient(TcpClient client)
{
    using (client)
    using (var stream = client.GetStream())
    {
        var buffer = new byte[32 * 1024];

        while (true)
        {
            int read;
            try
            {
                read = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length));
            }
            catch (IOException)
            {
                return;
            }

            if (read == 0)
            {
                return;
            }

            try
            {
                await stream.WriteAsync(buffer.AsMemory(0, read));
            }
            catch (IOException)
            {
                return;
            }
        }
    }
}
