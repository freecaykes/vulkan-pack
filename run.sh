#!/usr/bin/env bash
# Run a model with llama.cpp (Vulkan). Despite the name, any GGUF model works.
#
# Usage: ./04-run-qwen3.sh [options] [server|chat|bench]
#   -m, --model  MODEL   HF repo[:quant] (e.g. Qwen/Qwen3-8B-GGUF:Q4_K_M) or path to a .gguf file
#   -p, --port   PORT    server port                  (default: 8080)
#   -H, --host   HOST    server bind address          (default: 0.0.0.0, or 127.0.0.1 when MCP is on)
#   -n, --ngl    N       layers offloaded to GPU      (default: 99)
#   -c, --ctx    N       context size                 (default: 8192)
#   -d, --dir    PATH    llama.cpp checkout           (default: ~/llama.cpp)
#       --mcp-config FILE   your MCP/web-UI config JSON (see mcp.example.json); server mode only
#       --allow-remote   with MCP on, allow binding beyond localhost (the MCP proxy is an open relay!)
#   -h, --help
# Env vars (MODEL, PORT, HOST, NGL, CTX, LLAMA_DIR, MCP_CONFIG) set defaults; flags override them.
# Any args after "--" are passed straight to llama.cpp.
set -euo pipefail
[ -f /etc/profile.d/wsl-vulkan.sh ] && source /etc/profile.d/wsl-vulkan.sh
# Flag names differ between llama.cpp versions (--webui-* vs --ui-*); pick whichever this build has.
mcp_args() {  # mcp_args LLAMA_SERVER_BIN CONFIG_FILE  -> sets MCP_ARGS
  local help p=webui
  help="$("$1" --help 2>&1 || true)"
  if ! grep -qE -- '--(\[no-\])?webui-mcp-proxy' <<<"$help" && grep -qE -- '--(\[no-\])?ui-mcp-proxy' <<<"$help"; then p=ui; fi
  MCP_ARGS=(--jinja "--$p-mcp-proxy" "--$p-config-file" "$2")
}

MODEL="${MODEL:-Qwen/Qwen3-4B-GGUF:Q4_K_M}"
PORT="${PORT:-8080}"
HOST="${HOST:-}"
NGL="${NGL:-99}"
CTX="${CTX:-8192}"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
MCP_CONFIG="${MCP_CONFIG:-}"
ALLOW_REMOTE=0
MODE="server"
EXTRA=()

usage() { sed -n '/^# Usage/,/^set -/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--model) MODEL="$2"; shift 2 ;;
    -p|--port)  PORT="$2";  shift 2 ;;
    -H|--host)  HOST="$2";  shift 2 ;;
    -n|--ngl)   NGL="$2";   shift 2 ;;
    -c|--ctx)   CTX="$2";   shift 2 ;;
    -d|--dir)   LLAMA_DIR="$2"; shift 2 ;;
    --mcp-config) MCP_CONFIG="$2"; shift 2 ;;
    --allow-remote) ALLOW_REMOTE=1; shift ;;
    -h|--help)  usage 0 ;;
    server|chat|bench) MODE="$1"; shift ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done

BIN="$LLAMA_DIR/build/bin"
[ -x "$BIN/llama-server" ] || { echo "llama.cpp not built at $BIN (run 03-build-llamacpp.sh)"; exit 1; }

if [ -n "$MCP_CONFIG" ] && [ "$MODE" != "server" ]; then
  echo "NOTE: MCP only applies to server mode (the web UI); ignoring --mcp-config." >&2
  MCP_CONFIG=""
fi
if [ -z "$HOST" ]; then
  if [ -n "$MCP_CONFIG" ] && [ "$ALLOW_REMOTE" = 0 ]; then HOST="127.0.0.1"; else HOST="0.0.0.0"; fi
fi
if [ -n "$MCP_CONFIG" ] && [[ "$HOST" != 127.* && "$HOST" != "localhost" && "$HOST" != "::1" ]]; then
  echo "WARNING: MCP proxy is on and the server is bound to $HOST. Anyone who can reach it can make the" >&2
  echo "         server fetch arbitrary URLs. Only do this on a trusted network (e.g. Tailscale)." >&2
fi

# Local .gguf file -> -m ; otherwise treat as Hugging Face repo[:quant] -> -hf
if [[ "$MODEL" == *.gguf ]]; then
  [ -f "$MODEL" ] || { echo "Model file not found: $MODEL"; exit 1; }
  MODEL_ARGS=(-m "$MODEL")
else
  MODEL_ARGS=(-hf "$MODEL")
fi

echo "Mode: $MODE | Model: $MODEL | Port: $PORT | Host: $HOST | NGL: $NGL | Ctx: $CTX | MCP: ${MCP_CONFIG:-off}"
"$BIN/llama-server" --list-devices || true

case "$MODE" in
  server)
    MCP_ARGS=()
    if [ -n "$MCP_CONFIG" ]; then
      [ -f "$MCP_CONFIG" ] || { echo "MCP config not found: $MCP_CONFIG"; exit 1; }
      mcp_args "$BIN/llama-server" "$MCP_CONFIG"
    fi
    exec "$BIN/llama-server" "${MODEL_ARGS[@]}" -ngl "$NGL" -c "$CTX" --host "$HOST" --port "$PORT" \
      "${MCP_ARGS[@]}" "${EXTRA[@]}" ;;
  chat)   exec "$BIN/llama-cli"    "${MODEL_ARGS[@]}" -ngl "$NGL" -c "$CTX" -cnv "${EXTRA[@]}" ;;
  bench)  exec "$BIN/llama-bench"  "${MODEL_ARGS[@]}" -ngl "$NGL" "${EXTRA[@]}" ;;
esac
