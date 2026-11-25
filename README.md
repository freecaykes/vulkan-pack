# WSL2 + AMD (Radeon RX 5600 XT) + Vulkan on Debian 13

## Installation

Installation comes in multiple parts, one for installing the latest AMD Adrenalin driver on Windows (Powershell) and installing the lib vulkan dependencies on WSL.

1. Windows: install latest AMD Adrenalin driver, reboot, run `00-windows-prep.ps1`
2. WSL: `chmod +x *.sh && ./run-all.sh`  (or run 01-*.sh -> 02 -> 03 by hand)
3. `./04-run-qwen3.sh server` (or `chat` / `bench`)

How it works: WSL2 has no native AMD Vulkan driver. Mesa's `dzn` translates
Vulkan to D3D12, which goes through /dev/dxg to the Windows AMD driver.

Notes:
- If `vulkaninfo` shows only llvmpipe, the GPU isn't being used (CPU fallback).
- If 01 says no dzn ICD, your Mesa package lacks dzn; build Mesa with
  `-Dvulkan-drivers=microsoft-experimental`.
- dzn is a translation layer: expect slower speed than native Windows Vulkan,
  and some llama.cpp shader/feature failures are possible. If it errors or is
  slow, compare against the native Windows llama.cpp Vulkan build.
- Add `-ngl 0` (set NGL=0) to test CPU-only; lower NGL if you run out of VRAM (6 GB).

## Parameters
Both `run-all.sh` and `04-run-qwen3.sh` accept `--model`, `--port`, `--host`, `--ngl`, `--ctx`, `--dir`
(or env vars MODEL, PORT, HOST, NGL, CTX, LLAMA_DIR). Model can be a Hugging Face `repo[:quant]` or a local `.gguf` path.

    ./run-all.sh --model Qwen/Qwen3-8B-GGUF:Q4_K_M --port 9000 --run server
    ./04-run-qwen3.sh --model ~/models/qwen3-4b-q4.gguf --port 8081 --ctx 16384
    ./04-run-qwen3.sh --port 9000 chat -- --temp 0.6     # args after -- go to llama.cpp

## "dzn ICD not found" error
Debian's `mesa-vulkan-drivers` can lack the dzn driver. Build it from source (this is where
`-Dvulkan-drivers=microsoft-experimental` goes - it's in `01b-build-mesa-dzn.sh`):

    ./01b-build-mesa-dzn.sh && ./01-setup-wsl-vulkan.sh
    # or, all at once:
    ./run-all.sh --build-mesa

Installs to /opt/mesa-dzn (override with MESA_PREFIX). Pin a Mesa version with `--ref mesa-25.0.7`
(or `--mesa-ref` on run-all.sh) if the newest tag needs a newer meson/LLVM than Debian 13 provides.

Note: Debian has no unversioned `libclc-dev` / `libllvmspirvlib-dev`. `01b` auto-picks the highest LLVM
version with all needed packages (LLVM 19 on trixie). Force one with `LLVM_VER=19 ./01b-build-mesa-dzn.sh`.
