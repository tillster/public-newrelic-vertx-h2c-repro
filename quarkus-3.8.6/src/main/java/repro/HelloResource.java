package repro;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/**
 * Minimal Quarkus endpoint for reproducing a New Relic Java agent issue. See the README at the repository root.
 *
 * <p>Quarkus serves HTTP with Vert.x and keeps Vert.x's default of h2c enabled, so the first request on each keep-alive
 * connection is affected the same way as in the plain Vert.x folders. System property: {@code -Dport=8080}.
 */
@Path("/")
public class HelloResource {

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String hello() {
        return "ok\n";
    }
}
