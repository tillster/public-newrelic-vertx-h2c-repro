package repro;

import io.vertx.core.Vertx;
import io.vertx.core.http.HttpServerOptions;

/**
 * Minimal Vert.x HTTP server for reproducing a New Relic Java agent issue. See the README at the repository root.
 *
 * <p>System properties: {@code -Dport=8080} (default 8080) and {@code -Dh2c=false} to turn h2c off for comparison.
 */
public final class ReproServer {

    private ReproServer() {
    }

    public static void main(String[] args) {
        int port = Integer.getInteger("port", 8080);
        boolean h2c = Boolean.parseBoolean(System.getProperty("h2c", "true"));
        HttpServerOptions options = new HttpServerOptions().setHttp2ClearTextEnabled(h2c);

        Vertx.vertx()
                .createHttpServer(options)
                .requestHandler(request -> request.response().putHeader("content-type", "text/plain").end("ok\n"))
                .listen(port)
                .onSuccess(server -> System.out.println(
                        "Listening on port " + server.actualPort() + " with h2c " + (h2c ? "enabled" : "disabled")))
                .onFailure(error -> {
                    error.printStackTrace();
                    System.exit(1);
                });
    }
}
