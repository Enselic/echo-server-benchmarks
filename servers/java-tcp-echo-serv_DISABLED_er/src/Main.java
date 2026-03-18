import java.io.IOException;
import java.net.ServerSocket;
import java.net.Socket;

public final class Main {
    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            System.err.println("usage: java-echo-server <port>");
            System.exit(2);
        }

        int port;
        try {
            port = Integer.parseInt(args[0]);
        } catch (NumberFormatException ex) {
            System.err.println("port must be an integer");
            System.exit(2);
            return;
        }

        if (port < 1 || port > 65535) {
            System.err.println("port must be in range 1-65535");
            System.exit(2);
        }

        var server = new ServerSocket(port);

        while (true) {
            Socket socket = server.accept();
            new Thread(() -> handleClient(socket)).start();
        }
    }

    private static void handleClient(Socket socket) {
        try (socket;
             var in = socket.getInputStream();
             var out = socket.getOutputStream()) {

            byte[] buffer = new byte[32 * 1024];
            while (true) {
                int read = in.read(buffer);
                if (read <= 0) {
                    return;
                }
                out.write(buffer, 0, read);
                out.flush();
            }
        } catch (IOException ignored) {
        }
    }
}
