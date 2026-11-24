# public-newrelic-vertx-h2c-repro

Minimal reproduction for [newrelic/newrelic-java-agent#NNNN](https://github.com/newrelic/newrelic-java-agent/issues/NNNN).

On a Vert.x 4 HTTP server with HTTP/2 cleartext (h2c) enabled, which is the Vert.x default, the New Relic Java agent
keeps the transaction for the first request on each keep-alive connection open. It stays open until the connection
closes or `token_timeout` expires (180 s by default).

Vert.x builds the connection while it reads that first request, and the agent's `vertx-core` instrumentation stores a
token for the listener on the connection's close future. The request's response time is correct, but its transaction
only finishes when that token is released.

Quarkus HTTP servers built on Vert.x 4 keep h2c enabled by default, so they are affected the same way.

## One folder per Vert.x version

Each folder holds the same small HTTP server, built against a different Vert.x version. There is one folder for each of
the agent's `vertx-core` instrumentation modules:

| Folder         | Vert.x | Agent module       | Leaks a token? | `-Dh2c=false` available |
|----------------|--------|--------------------|----------------|-------------------------|
| `vertx-4.0.3`  | 4.0.3  | `vertx-core-4.0.0` | yes            | no                      |
| `vertx-4.2.5`  | 4.2.5  | `vertx-core-4.1.0` | yes            | no                      |
| `vertx-4.4.9`  | 4.4.9  | `vertx-core-4.3.2` | yes            | no                      |
| `vertx-4.5.0`  | 4.5.0  | `vertx-core-4.5.0` | yes            | no                      |
| `vertx-4.5.7`  | 4.5.7  | `vertx-core-4.5.1` | yes            | yes                     |
| `vertx-5.0.12` | 5.0.12 | `vertx-core-5.0.0` | no (control)   | yes                     |

Vert.x added `HttpServerOptions#setHttp2ClearTextEnabled` in 4.5.1, so older versions always have h2c on.

## Requirements

- JDK 11 or later, Maven 3.6.3 or later, and `nc` (netcat).
- The New Relic Java agent:
  - 8.8.0 or later for Vert.x 4.0 to 4.4;
  - 8.9.0 or later for Vert.x 4.5;
  - a release with Vert.x 5 support for `vertx-5.0.12` (9.5.0 has it).

## Steps

1. Build every folder. Each one produces `<folder>/target/repro.jar`:

   ```bash
   mvn package
   ```

   To build a single folder, for example `vertx-4.5.7`: `mvn -pl vertx-4.5.7 -am package`.

2. Download the agent into this directory (unzipping creates `newrelic/`) and set your license key:

   ```bash
   curl -O https://download.newrelic.com/newrelic/java-agent/newrelic-agent/current/newrelic-java.zip
   unzip newrelic-java.zip
   export NEW_RELIC_LICENSE_KEY=<your license key>
   ```

3. Start one folder's server with the agent. The flags shorten `token_timeout` to 15 s and log token activity:

   ```bash
   java -javaagent:newrelic/newrelic.jar \
     -Dnewrelic.config.app_name=vertx-h2c-token-repro \
     -Dnewrelic.config.token_timeout=15 \
     -Dnewrelic.config.token_debug=true \
     -Dnewrelic.config.log_level=finest \
     -jar vertx-4.5.7/target/repro.jar
   ```

   It prints `Listening on port 8080 with h2c enabled`.

4. In a second terminal, send one request on a keep-alive connection and keep the connection open for 30 s:

   ```bash
   (printf 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n'; sleep 30) | nc localhost 8080
   ```

   You get `HTTP/1.1 200 OK` and `ok` back right away. The macOS `nc` exits after the 30 s; some Linux `nc` builds keep
   the connection open until you press Ctrl+C.

5. Look at the agent log:

   ```bash
   grep -E 'Timing out token|for request: / finished' newrelic/logs/newrelic_agent.log
   ```

   Within about 45 s of the request, you see the token time out and only then the request's transaction finish:

   ```
   Timing out token com.newrelic.agent.TokenImpl@... on transaction com.newrelic.agent.Transaction@...
   Transaction WebTransaction/NettyDispatcher/NettyDispatcher for request: / finished 42ms com.newrelic.agent.Transaction@...
   ```

   The response time is a few milliseconds, but the transaction stayed open until the token timed out. The timeout
   isn't logged at exactly 15 s, because the agent notices timed-out tokens on a periodic check, or when the connection
   closes.

To try another version, stop the server and repeat steps 3 to 5 with that folder's jar. The agent log keeps growing
across runs, so look at its newest lines.

## Compare

- `vertx-5.0.12`: no `Timing out token` line. The `finished` line appears right after the request.
- `vertx-4.5.7` or `vertx-5.0.12` with `-Dh2c=false` placed before `-jar`: the server prints
  `Listening on port 8080 with h2c disabled`. There is no `Timing out token` line, and the `finished` line appears right
  after the request.
- Any folder, with the request sent with `Connection: close`:

  ```bash
  (printf 'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n'; sleep 30) | nc localhost 8080
  ```

  The server closes the connection after responding, so the transaction finishes right away, even though `nc` waits
  out the 30 s.

## Notes

- Tested on Java 21 with agent 9.5.0 (every folder) and agent 8.23.0 (`vertx-4.2.5` and `vertx-4.5.7`).
- `-Dport=<port>`, placed before `-jar`, changes the port (default 8080).
