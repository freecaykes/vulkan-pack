#!/usr/bin/env bash
# Run a model with llama.cpp (Vulkan). Despite the name, any GGUF model works.
#
# Usage: ./04-run-qwen3.sh [options] [server|chat|bench]
#   -m, --model  MODEL   HF repo[:quant] (e.g. Qwen/Qwen3-8B-GGUF:Q4_K_M) or path to a .gguf file
#   -p, --port   PORT    server port                  (default: 8080)
#   -H, --host   HOST    server bind address          (default: 0.0.0.0)
#   -n, --ngl    N       layers offloaded to GPU      (default: 99)
#   -c, --ctx    N       context size                 (default: 8192)
#   -d, --dir    PATH    llama.cpp checkout           (default: ~/llama.cpp)
#   -h, --help
# Env vars (MODEL, PORT, HOST, NGL, CTX, LLAMA_DIR) set defaults; flags override them.
# Any args after "--" are passed straight to llama.cpp.
set -euo pipefail
[ -f /etc/profile.d/wsl-vulkan.sh ] && source /etc/profile.d/wsl-vulkan.sh

MODEL="${MODEL:-Qwen/Qwen3-4B-GGUF:Q4_K_M}"
PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"
NGL="${NGL:-99}"
CTX="${CTX:-8192}"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
MODE="server"
EXTRA=()

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--model) MODEL="$2"; shift 2 ;;
    -p|--port)  PORT="$2";  shift 2 ;;
    -H|--host)  HOST="$2";  shift 2 ;;
    -n|--ngl)   NGL="$2";   shift 2 ;;
    -c|--ctx)   CTX="$2";   shift 2 ;;
    -d|--dir)   LLAMA_DIR="$2"; shift 2 ;;
    -h|--help)  usage 0 ;;
    server|chat|bench) MODE="$1"; shift ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done

BIN="$LLAMA_DIR/build/bin"
[ -x "$BIN/llama-server" ] || { echo "llama.cpp not built at $BIN (run 03-build-llamacpp.sh)"; exit 1; }

# Local .gguf file -> -m ; otherwise treat as Hugging Face repo[:quant] -> -hf
if [[ "$MODEL" == *.gguf ]]; then
  [ -f "$MODEL" ] || { echo "Model file not found: $MODEL"; exit 1; }
  MODEL_ARGS=(-m "$MODEL")
else
  MODEL_ARGS=(-hf "$MODEL")
fi

echo "Mode: $MODE | Model: $MODEL | Port: $PORT | Host: $HOST | NGL: $NGL | Ctx: $CTX"
"$BIN/llama-server" --list-devices || true

case "$MODE" in
  server) exec "$BIN/llama-server" "${MODEL_ARGS[@]}" -ngl "$NGL" -c "$CTX" --host "$HOST" --port "$PORT" "${EXTRA[@]}" ;;
  chat)   exec "$BIN/llama-cli"    "${MODEL_ARGS[@]}" -ngl "$NGL" -c "$CTX" -cnv "${EXTRA[@]}" ;;
  bench)  exec "$BIN/llama-bench"  "${MODEL_ARGS[@]}" -ngl "$NGL" "${EXTRA[@]}" ;;
esac

