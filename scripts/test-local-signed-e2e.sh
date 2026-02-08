#!/usr/bin/env bash
set -euo pipefail

# End-to-end local runtime validation for a signed Compote binary.
# Usage:
#   COMPOTE_BIN=/path/to/compote ./scripts/test-local-signed-e2e.sh

COMPOTE_BIN="${COMPOTE_BIN:-compote}"
WORKDIR="${WORKDIR:-/tmp/compote-e2e-signed}"

if ! command -v "$COMPOTE_BIN" >/dev/null 2>&1; then
  echo "error: compote binary not found: $COMPOTE_BIN" >&2
  exit 1
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found; install with: brew install container" >&2
  exit 1
fi

if ! command -v socat >/dev/null 2>&1; then
  echo "error: socat not found; install with: brew install socat" >&2
  exit 1
fi

cleanup() {
  "$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e down --volumes >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$WORKDIR"

cat > "$WORKDIR/compote.yml" <<'YAML'
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "18080:80"
  worker:
    image: alpine:3.20
    command: ["sh", "-c", "while true; do echo worker-alive; sleep 2; done"]
YAML

echo "==> starting container runtime"
container system start >/dev/null

echo "==> checking setup"
"$COMPOTE_BIN" setup

echo "==> validating compose config"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e config >/dev/null

echo "==> starting services"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e up -d >/dev/null
sleep 5

echo "==> checking service list"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e ps

echo "==> scaling worker"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e scale worker=2 >/dev/null
sleep 3
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e ps

echo "==> reading replica logs"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e logs --tail 5 worker#2 >/dev/null

echo "==> exec into specific replica"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e exec worker#2 echo e2e-ok >/dev/null

echo "==> lifecycle controls"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e stop worker#2 >/dev/null
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e start worker#2 >/dev/null
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e restart web#1 >/dev/null

echo "==> tearing down"
"$COMPOTE_BIN" -f "$WORKDIR/compote.yml" -p compote-e2e down --volumes >/dev/null
echo "ok: signed-binary e2e scenario passed"
