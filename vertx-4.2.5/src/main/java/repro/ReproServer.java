package repro;

import io.vertx.core.Vertx;
import io.vertx.core.http.HttpServerOptions;

/**
 * Minimal Vert.x HTTP server for reproducing a New Relic Java agent issue. See the README at the repository root.
 *
 * <p>System property: {@code -Dport=8080} (default 8080). This Vert.x version has no option to turn h2c off.
 */
public final class ReproServer {

    private ReproServer() {
    }

    public static void main(String[] args) {
        int port = Integer.getInteger("port", 8080);
        HttpServerOptions options = new HttpServerOptions();

        Vertx.vertx()
                .createHttpServer(options)
                .requestHandler(request -> request.response().putHeader("content-type", "text/plain").end("ok\n"))
                .listen(port)
                .onSuccess(server -> System.out.println(
                        "Listening on port " + server.actualPort() + " with h2c enabled (it can't be turned off here)"))
                .onFailure(error -> {
                    error.printStackTrace();
                    System.exit(1);
                });
    }
}
