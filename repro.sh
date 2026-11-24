#!/usr/bin/env bash
# One-command reproduction. Builds a folder's server, starts it under the New Relic Java agent, sends one request on a
# keep-alive connection, keeps the connection open, and reports whether the agent timed out a token for that request.
#
# Usage: ./repro.sh [folder]        (default folder: vertx-4.5.7)
#
# Environment variables (all optional):
#   NEW_RELIC_LICENSE_KEY  Report to your New Relic account. Without it the agent runs log-only: it is pointed at a
#                          closed local port, so nothing is sent anywhere, and the verdict comes from the agent log.
#   NEWRELIC_AGENT_JAR     Use this newrelic.jar instead of downloading the current agent.
#   PORT                   Server port (default 8080).
#   HOLD_SECONDS           How long to keep the connection open after the response (default 50).
#   JAVA_OPTS              Extra JVM flags, placed before -jar, for example JAVA_OPTS=-Dh2c=false.
set -euo pipefail

cd "$(dirname "$0")"
FOLDER="${1:-vertx-4.5.7}"
FOLDER="${FOLDER%/}"
PORT="${PORT:-8080}"
HOLD_SECONDS="${HOLD_SECONDS:-50}"
WORK="$PWD/.repro"
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"

if [ ! -f "$FOLDER/pom.xml" ]; then
  echo "No such folder: $FOLDER. Pick one of:" >&2
  ls -d vertx-*/ quarkus-*/ 2>/dev/null | sed 's#/$##; s#^#  #' >&2
  exit 2
fi
mkdir -p "$WORK/logs"

# 1. Build the server if it isn't built yet.
JAR="$FOLDER/target/repro.jar"
if [ ! -f "$JAR" ]; then
  echo "Building $FOLDER ..."
  ./mvnw -q -B -pl "$FOLDER" -am package
fi

# 2. Get the agent.
AGENT="${NEWRELIC_AGENT_JAR:-$WORK/newrelic/newrelic.jar}"
if [ ! -f "$AGENT" ]; then
  echo "Downloading the current New Relic Java agent ..."
  curl -fsSL -o "$WORK/newrelic-java.zip" \
    https://download.newrelic.com/newrelic/java-agent/newrelic-agent/current/newrelic-java.zip
  unzip -q -o "$WORK/newrelic-java.zip" -d "$WORK"
fi

# 3. Agent settings for this run: a short token_timeout and token logging.
LOG="$WORK/logs/$FOLDER.log"
OUT="$WORK/logs/$FOLDER.out"
CONFIG="$WORK/newrelic-repro.yml"
rm -f "$LOG" "$OUT"
{
  echo "common: &default_settings"
  echo "  app_name: vertx-h2c-token-repro"
  echo "  token_timeout: 15"
  echo "  token_debug: true"
  echo "  log_level: finest"
  echo "  log_file_path: $WORK/logs"
  echo "  log_file_name: $FOLDER.log"
  if [ -z "${NEW_RELIC_LICENSE_KEY:-}" ]; then
    # Log-only mode: a placeholder key and a closed local port, so the agent never sends data anywhere.
    echo "  license_key: '0000000000000000000000000000000000000000'"
    echo "  host: 127.0.0.1"
    echo "  port: 9"
  fi
  echo "production:"
  echo "  <<: *default_settings"
} > "$CONFIG"
if [ -z "${NEW_RELIC_LICENSE_KEY:-}" ]; then
  echo "No NEW_RELIC_LICENSE_KEY set: running the agent log-only (nothing is sent to New Relic)."
fi

# 4. Start the server under the agent.
echo "Starting $FOLDER on port $PORT ..."
# shellcheck disable=SC2086  # JAVA_OPTS is split into separate flags on purpose.
"$JAVA" -javaagent:"$AGENT" -Dnewrelic.config.file="$CONFIG" -Dnewrelic.environment=production \
  -Dport="$PORT" ${JAVA_OPTS:-} -jar "$JAR" > "$OUT" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 240); do
  grep -q "Listening on" "$OUT" && break
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "The server exited before it started listening:" >&2
    tail -20 "$OUT" >&2
    exit 1
  fi
  sleep 0.5
done
if ! grep -q "Listening on" "$OUT"; then
  echo "The server did not start within 2 minutes. See $OUT" >&2
  exit 1
fi
grep -m1 "Listening on" "$OUT" | sed 's/^/  /'

# 5. One request on a keep-alive connection, then keep the connection open.
exec 3<>"/dev/tcp/127.0.0.1/$PORT"
printf 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n' >&3
IFS= read -r STATUS_LINE <&3
echo "  Response: ${STATUS_LINE%$'\r'}"
echo "Keeping the connection open for $HOLD_SECONDS s (token_timeout is 15 s; the agent checks for timeouts periodically) ..."
sleep "$HOLD_SECONDS"
exec 3>&-
sleep 2

# 6. Verdict from the agent log.
echo
if grep -q "Timing out token" "$LOG"; then
  echo "RESULT: LEAK REPRODUCED. The agent timed out a token for the request while the connection was still open,"
  echo "so the request's transaction stayed open even though the response was sent right away."
else
  echo "RESULT: no leak. No token timed out; the request's transaction finished when the response was sent."
fi
echo
echo "Relevant agent log lines ($LOG):"
grep -E "Timing out token|for request: / finished" "$LOG" | sed 's/^/  /' || echo "  (none)"
