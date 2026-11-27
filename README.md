# Vulkan backend llama.cpp install with APT (native Linux and WSL2 + AMD)

## Installation

Two paths: a native Linux distro (shell scripts only) or WSL2 (Windows prep in PowerShell, then shell scripts in WSL).

### Native Linux

No PowerShell step and no dzn needed: the distro's Vulkan driver is used directly
(RADV for AMD, ANV for Intel, or the NVIDIA proprietary driver). `01` detects native
Linux and skips all WSL/dzn setup.

```bash
chmod +x *.sh

./01-vulkan-setup.sh        # installs Vulkan packages; skips dzn on native Linux
./02-verify-vulkan.sh       # confirms a real GPU Vulkan device (not llvmpipe)
./03-install-llama.sh       # clones and builds llama.cpp with GGML_VULKAN=ON
./run.sh server             # start the model (or: chat / bench)
```

Or run the whole sequence with `./install.sh --run server`.

### WSL2

Installation has two parts: a Windows prep step (PowerShell) and the Vulkan/llama.cpp
setup inside WSL (shell scripts, run in order).

#### 1. Windows (PowerShell)

Install the latest AMD Adrenalin driver, reboot, then run the prep script from an
elevated PowerShell in this folder:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\00-windows-prep.ps1
```

#### 2. WSL (run the shell scripts in order)

```bash
chmod +x *.sh

./01-vulkan-setup.sh        # installs Mesa Vulkan packages, sets up dzn ICD
./02-verify-vulkan.sh       # confirms a real GPU Vulkan device (not llvmpipe)
./03-install-llama.sh       # clones and builds llama.cpp with GGML_VULKAN=ON
./run.sh server             # start the model (or: chat / bench)
```

If `01-vulkan-setup.sh` reports **"dzn ICD not found"**, build Mesa's dzn driver,
then re-run step 01:

```bash
./01b-build-mesa-dzn.sh
./01-vulkan-setup.sh
./02-verify-vulkan.sh
```

Or let `install.sh` drive the whole sequence:

```bash
./install.sh                    # setup -> verify -> build
./install.sh --build-mesa       # build dzn from source if the distro Mesa lacks it
./install.sh --run server       # setup -> verify -> build -> run
```

On WSL2: WSL has no native AMD Vulkan driver. Mesa's `dzn` translates Vulkan to
D3D12, which goes through `/dev/dxg` to the Windows AMD driver. On native Linux the
distro driver is used directly, so dzn and `/dev/dxg` are not involved.

### Docker

Prefer containers? A single image works on both WSL2 and native Linux. See
[docker/README.md](docker/README.md) for building the image, the required device
passthrough (`/dev/dxg` on WSL2, `/dev/dri` on Linux), and running it with a model
volume and environment variables.

### "dzn ICD not found" error (WSL2 only)

Debian's `mesa-vulkan-drivers` can lack dzn. Build it from source
(`-Dvulkan-drivers=microsoft-experimental`, set in `01b-build-mesa-dzn.sh`):

```bash
./01b-build-mesa-dzn.sh && ./01-vulkan-setup.sh
# or, all at once:
./install.sh --build-mesa
```

Installs to `/opt/mesa-dzn` (override with `MESA_PREFIX`). Pin a Mesa version with
`--ref mesa-25.0.7` (or `--mesa-ref` on `install.sh`) if the newest tag needs a newer
meson/LLVM than Debian 13 provides.

Note: Debian has no unversioned `libclc-dev` / `libllvmspirvlib-dev`. `01b` auto-picks the highest LLVM
version with all needed packages (LLVM 19 on trixie). Force one with `LLVM_VER=19 ./01b-build-mesa-dzn.sh`.

## MCP (tool use via llama-server's web UI)

llama-server has no MCP client of its own. MCP runs in the built-in web UI (your browser); the server only
provides a CORS proxy (`--webui-mcp-proxy`, or `--ui-mcp-proxy` on newer builds) and loads a UI config file
(`--webui-config-file`). Only HTTP(S) MCP servers (streamable HTTP) work; stdio and legacy SSE servers need a
bridge. Server mode only (not chat/bench). The model must support tool calling (`--jinja` is added for you).

Copy `examples/mcp.example.json`, edit it, and pass it with `--mcp-config FILE` (or `MCP_CONFIG=FILE`):

```bash
./run.sh --mcp-config my-mcp.json server
MCP_CONFIG=my-mcp.json ./run.sh server
./install.sh --mcp-config my-mcp.json --run server
```

When MCP is on, `run.sh` binds to `127.0.0.1` by default. Pass `--allow-remote` (or `-H`) to expose it; the
proxy is an open relay, so anyone who can reach the server can make it fetch arbitrary URLs.

Docker: mount the config read-only and point `MCP_CONFIG` at it inside the container. The image binds to
`0.0.0.0` by default, so also set `HOST=127.0.0.1` unless you intend to expose it (the `-p` mapping still
publishes it to the host):

```bash
docker run --rm -it --device /dev/dri --group-add video --group-add render \
    -p 8080:8080 -v ~/models:/models \
    -v "$PWD/my-mcp.json:/config/mcp.json:ro" \
    -e MODEL=Qwen/Qwen3-4B-GGUF:Q4_K_M -e HOST=127.0.0.1 \
    -e MCP_CONFIG=/config/mcp.json \
    llama-vulkan:latest server
```

The file is used exactly as written, so it will contain any API keys: don't commit or share it.

## Scripts

| Script | Purpose |
| --- | --- |
| `01-vulkan-setup.sh` | Installs `mesa-vulkan-drivers`, `libvulkan1`, `vulkan-tools`, `mesa-utils`. On native Linux it stops there and uses the system driver; on WSL2 it adds `/usr/lib/wsl/lib` to the loader path, locates the dzn ICD, and writes `/etc/profile.d/wsl-vulkan.sh`. Set `BUILD_MESA=1` (WSL) to build dzn automatically; `MESA_PREFIX` (default `/opt/mesa-dzn`) is where a source build is looked for. |
| `01b-build-mesa-dzn.sh` | WSL2 only. Builds Mesa's dzn driver from source (`-Dvulkan-drivers=microsoft-experimental`). Auto-detects the newest usable LLVM; installs to `/opt/mesa-dzn`. Options: `--ref TAG`, `--prefix DIR`, `--src DIR`, `--platforms LIST`. Env: `MESA_REF`, `MESA_PREFIX`, `MESA_SRC`, `PLATFORMS`, `MICROSOFT_CLC`, `LLVM_VER`. |
| `02-verify-vulkan.sh` | On WSL2 checks `/dev/dxg` and the WSL GPU libs; on native Linux skips those. Both print `VK_ICD_FILENAMES` and run `vulkaninfo --summary`; fails if only llvmpipe is found. |
| `03-install-llama.sh` | Installs build deps, clones/updates llama.cpp into `LLAMA_DIR` (default `~/llama.cpp`), builds with `-DGGML_VULKAN=ON`. |
| `run.sh` | Runs a GGUF model via `llama-server` (`server`), `llama-cli` (`chat`), or `llama-bench` (`bench`). |
| `install.sh` | One-shot wrapper: `01` -> `02` -> `03`, optionally runs `04`. Works on native Linux and WSL2. Supports `--build-mesa`, `--mesa-ref`, `--skip-setup`, `--skip-build`, `--run MODE`. |

## Parameters

### NAME

`install.sh` - set up Vulkan (system driver on native Linux, dzn on WSL2) and build llama.cpp, optionally run a model
`run.sh` - run a GGUF model with llama.cpp (Vulkan)

### SYNOPSIS

```
install.sh [OPTIONS]
run.sh [OPTIONS] [server|chat|bench] [-- LLAMA_ARGS...]
```

### OPTIONS

Shared by `install.sh` and `run.sh`:

```
-m, --model MODEL   Hugging Face repo[:quant] or path to a .gguf file
                    (default: Qwen/Qwen3-4B-GGUF:Q4_K_M)
-p, --port PORT     server port (default: 8080)
-H, --host HOST     server bind address (default: 0.0.0.0, or 127.0.0.1 when MCP is on)
-n, --ngl N         layers offloaded to the GPU (default: 99)
-c, --ctx N         context size (default: 8192)
-d, --dir PATH      llama.cpp checkout (default: ~/llama.cpp)
    --mcp-config FILE  MCP/web UI config JSON (see examples/mcp.example.json);
                    server mode only (with install.sh, requires --run server)
    --allow-remote  with MCP on, bind beyond localhost (the MCP proxy is an open relay)
-h, --help          print usage and exit
```

`install.sh` only:

```
-r, --run MODE      after building, run: server, chat, or bench
    --build-mesa    build dzn from source if the distro Mesa lacks it (WSL2, runs 01b)
    --mesa-ref TAG  Mesa tag to build (default: latest stable)
    --skip-setup    skip steps 01 and 02 (Vulkan already working)
    --skip-build    skip step 03 (llama.cpp already built)
```

`run.sh` only:

```
server|chat|bench   run llama-server, llama-cli, or llama-bench (default: server)
--                  pass all remaining arguments straight to llama.cpp
```

### ENVIRONMENT

```
MODEL       default model (see --model)
PORT        default server port
HOST        default bind address
NGL         default GPU layers
CTX         default context size
LLAMA_DIR   default llama.cpp checkout
MCP_CONFIG  default MCP/web UI config JSON (server mode only; see --mcp-config)
```

Flags override environment variables.

### EXAMPLES

```bash
./install.sh --model Qwen/Qwen3-8B-GGUF:Q4_K_M --port 9000
./run.sh --model ~/models/qwen3-4b-q4.gguf --port 8081 --ctx 16384
./run.sh --port 9000 chat -- --temp 0.6     # args after -- go to llama.cpp

# MCP (server mode): tools in the web UI, bound to localhost by default
./run.sh --mcp-config my-mcp.json server
MCP_CONFIG=my-mcp.json ./run.sh server
./install.sh --mcp-config my-mcp.json --run server
```


## Troubleshooting

- If `vulkaninfo` shows only llvmpipe, the GPU isn't being used (CPU fallback). On native Linux,
  install the GPU driver: `mesa-vulkan-drivers` for AMD/Intel, or the NVIDIA proprietary driver.
- On native Linux, `01`/`02` skip the `/dev/dxg`, WSL GPU lib, and dzn checks automatically.
- If `01-vulkan-setup.sh` says no dzn ICD (WSL2), your Mesa package lacks dzn; build it with
  `./01b-build-mesa-dzn.sh` (or `./install.sh --build-mesa`).
- `01b-build-mesa-dzn.sh` is WSL2-only and installs to `/opt/mesa-dzn` (override with `MESA_PREFIX`). Pin a Mesa
  version with `--ref mesa-25.0.7` (or `--mesa-ref` on `install.sh`) if the newest tag needs a newer
  meson/LLVM than Debian 13 provides.
- Debian has no unversioned `libclc-dev` / `libllvmspirvlib-dev`. `01b` auto-picks the highest LLVM
  version with all needed packages (LLVM 19 on trixie). Force one with `LLVM_VER=19 ./01b-build-mesa-dzn.sh`.
- dzn is a translation layer (WSL2 only): expect slower speed than native Windows Vulkan, and some llama.cpp
  shader/feature failures are possible. If it errors or is slow, compare against the native Windows
  llama.cpp Vulkan build.
- Add `-ngl 0` (set `NGL=0`) to test CPU-only; lower NGL if you run out of VRAM (6 GB).
