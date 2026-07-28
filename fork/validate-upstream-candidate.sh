#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: validate-upstream-candidate.sh vX.Y.Z}"
if [[ ! "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "invalid strict semantic version: $version" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/data" "$work_dir/home"

jq -e --arg version "$version" '
  .schema_version == 1
  and .repository == "Gentleman-Programming/engram"
  and .tag == $version
  and (.commit | test("^[0-9a-f]{40}$"))
' fork/upstream.json >/dev/null

go mod verify
go test ./...
go test -tags e2e ./internal/server/...
go build -ldflags="-X main.version=${version#v}" -o "$work_dir/engram" ./cmd/engram

HOME="$work_dir/home" ENGRAM_DATA_DIR="$work_dir/data" \
  "$work_dir/engram" doctor --json |
  jq -e '
    .status == "ok"
    and .summary.errors == 0
    and .summary.blocked == 0
  ' >/dev/null

mcp_output="$(
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"fork-validator","version":"1.0"}}}' |
    HOME="$work_dir/home" ENGRAM_DATA_DIR="$work_dir/data" \
      "$work_dir/engram" mcp --tools=agent
)"

printf '%s\n' "$mcp_output" |
  jq -s -e '
    any(
      .[];
      .jsonrpc == "2.0"
      and .id == 1
      and .result.protocolVersion == "2025-03-26"
      and .result.serverInfo.name == "engram"
      and (.result.capabilities.tools | type) == "object"
    )
  ' >/dev/null
