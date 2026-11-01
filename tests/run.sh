#!/usr/bin/env bash
# Runs every tests/<name>.jq through zorba-mcp over stdio JSON-RPC, the same
# way Claude Code talks to the server configured in .mcp.json, and compares
# the text of each run_query result with tests/<name>.expected.
#
# The server command (image, mount, flags) is read from .mcp.json, so the
# tests exercise exactly what the demo runs. Requires docker and jq. Run from
# anywhere: tests/run.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image="$(jq -er '.mcpServers.zorba.args[] | select(startswith("ghcr.io/zorba-processor/zorba:"))' "$root/.mcp.json")"
echo "image: $image"

queries=("$root"/tests/*.jq)
[ "${#queries[@]}" -gt 0 ] || { echo "no queries in tests/" >&2; exit 1; }

# One session: initialize, then one tools/call per query (id = index + 2).
requests="$(
  jq -nc '{jsonrpc:"2.0",id:1,method:"initialize",params:{protocolVersion:"2025-11-25",capabilities:{},clientInfo:{name:"zorba-demo-tests",version:"1"}}}'
  jq -nc '{jsonrpc:"2.0",method:"notifications/initialized"}'
  i=2
  for q in "${queries[@]}"; do
    jq -nc --arg q "$(cat "$q")" --argjson id "$i" \
      '{jsonrpc:"2.0",id:$id,method:"tools/call",params:{name:"run_query",arguments:{query:$q}}}'
    i=$((i + 1))
  done
)"

# The server command is the one in .mcp.json, with the project directory
# substituted the way Claude Code expands ${CLAUDE_PROJECT_DIR:-.}.
[ "$(jq -r '.mcpServers.zorba.command' "$root/.mcp.json")" = docker ]
args=()
while IFS= read -r a; do
  args+=("${a//'${CLAUDE_PROJECT_DIR:-.}'/$root}")
done < <(jq -r '.mcpServers.zorba.args[]' "$root/.mcp.json")
echo "command: docker ${args[*]}"

responses="$(printf '%s\n' "$requests" | docker "${args[@]}")"

jq -e 'select(.id == 1) | .result.serverInfo.name == "zorba-mcp"' <<<"$responses" >/dev/null \
  || { echo "initialize failed:" >&2; echo "$responses" >&2; exit 1; }

failed=0
i=2
for q in "${queries[@]}"; do
  name="$(basename "$q" .jq)"
  expected="$root/tests/$name.expected"
  response="$(jq -c --argjson id "$i" 'select(.id == $id)' <<<"$responses")"
  if ! jq -e '.result.isError == false' <<<"$response" >/dev/null; then
    echo "FAIL $name: error response: $response"
    failed=1
  elif ! diff -u "$expected" <(jq -r '.result.content[0].text' <<<"$response"); then
    echo "FAIL $name: result differs from $name.expected"
    failed=1
  else
    echo "PASS $name"
  fi
  i=$((i + 1))
done
exit "$failed"
