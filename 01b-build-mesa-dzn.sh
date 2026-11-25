#!/usr/bin/env bash
# Build Mesa's dzn (Dozen) Vulkan driver from source. Use this when 01-setup-wsl-vulkan.sh
# reports "dzn ICD not found" (your distro's Mesa package was built without it).
# The flag you asked about, -Dvulkan-drivers=microsoft-experimental, is set below in `common`.
#
# Usage: ./01b-build-mesa-dzn.sh [--ref TAG] [--prefix DIR] [--src DIR] [--platforms LIST]
# Env:   MESA_REF (default: latest stable mesa-X.Y.Z tag), MESA_PREFIX (/opt/mesa-dzn),
#        MESA_SRC (~/mesa-dzn-src), PLATFORMS (x11), MICROSOFT_CLC (enabled),
#        LLVM_VER (default: auto-detect highest version Debian ships all needed packages for)
set -euo pipefail

MESA_REF="${MESA_REF:-}"
PREFIX="${MESA_PREFIX:-/opt/mesa-dzn}"
SRC="${MESA_SRC:-$HOME/mesa-dzn-src}"
PLATFORMS="${PLATFORMS:-x11}"
MICROSOFT_CLC="${MICROSOFT_CLC:-enabled}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) MESA_REF="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --src) SRC="$2"; shift 2 ;;
    --platforms) PLATFORMS="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -e /dev/dxg ] || { echo "ERROR: /dev/dxg missing - fix WSL GPU passthrough first (00-windows-prep.ps1)."; exit 1; }

echo "== Installing build dependencies =="
sudo apt-get update

# True only if apt has an installable candidate (apt-cache show also succeeds for virtual/replaced packages)
has_pkg() { local c; c="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')"; [ -n "$c" ] && [ "$c" != "(none)" ]; }

# Debian ships versioned LLVM packages (e.g. libclc-19-dev), not libclc-dev. Pick the highest
# version for which every LLVM-side package exists.
LLVM_VER="${LLVM_VER:-}"
if [ -z "$LLVM_VER" ]; then
  for v in 22 21 20 19 18 17 16 15; do
    if has_pkg "llvm-$v-dev" && has_pkg "libclang-$v-dev" && has_pkg "libclang-cpp$v-dev" \
       && has_pkg "libclc-$v-dev" && has_pkg "libllvmspirvlib-$v-dev"; then LLVM_VER="$v"; break; fi
  done
fi
[ -n "$LLVM_VER" ] || { echo "ERROR: no LLVM version with llvm/clang/libclc/spirv-translator dev packages all available."; exit 1; }
echo "Using LLVM $LLVM_VER"

pkgs=(build-essential git meson ninja-build pkg-config python3-mako python3-yaml python3-packaging
      bison flex glslang-tools libexpat1-dev zlib1g-dev libzstd-dev libdrm-dev libvulkan-dev
      libx11-xcb-dev libxcb-shm0-dev libxcb-dri2-0-dev libxcb-glx0-dev 
      libdirectx-headers-dev spirv-tools libspirv-tools-dev spirv-headers directx-headers-dev
      "llvm-$LLVM_VER-dev" "clang-$LLVM_VER" "libclang-$LLVM_VER-dev" "libclang-cpp$LLVM_VER-dev"
      "libclang-common-$LLVM_VER-dev" "libclc-$LLVM_VER-dev" "libllvmspirvlib-$LLVM_VER-dev")
[[ "$PLATFORMS" == *x11* ]] && pkgs+=(libx11-dev libxcb1-dev libxcb-dri3-dev libxcb-present-dev
      libxcb-sync-dev libxcb-randr0-dev libxcb-xfixes0-dev libxshmfence-dev libxrandr-dev)
[[ "$PLATFORMS" == *wayland* ]] && pkgs+=(libwayland-dev wayland-protocols)

avail=(); missing=()
for p in "${pkgs[@]}"; do
  if has_pkg "$p"; then avail+=("$p"); else missing+=("$p"); fi
done
sudo apt-get install -y "${avail[@]}"
[ ${#missing[@]} -gt 0 ] && echo "NOTE: no install candidate for: ${missing[*]} (meson will say if one is needed)"

# Make meson use the versioned LLVM
export LLVM_CONFIG="$(command -v "llvm-config-$LLVM_VER" || echo "/usr/lib/llvm-$LLVM_VER/bin/llvm-config")"
export PATH="/usr/lib/llvm-$LLVM_VER/bin:$PATH"
echo "LLVM_CONFIG=$LLVM_CONFIG"

if [ -z "$MESA_REF" ]; then
  MESA_REF="$(git ls-remote --tags --refs https://gitlab.freedesktop.org/mesa/mesa.git 'refs/tags/mesa-*' \
    | sed 's#.*refs/tags/##' | grep -E '^mesa-[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
fi
echo "== Cloning Mesa @ $MESA_REF =="
rm -rf "$SRC"
git clone --depth 1 --branch "$MESA_REF" https://gitlab.freedesktop.org/mesa/mesa.git "$SRC"
cd "$SRC"

common=(
  -Dbuildtype=release
  -Dprefix="$PREFIX"
  -Dvulkan-drivers=microsoft-experimental   # <-- builds dzn
  -Dgallium-drivers=
  -Dplatforms="$PLATFORMS"
  -Dllvm=enabled -Dshared-llvm=enabled
  -Dspirv-to-dxil=true
)
echo "== Configuring =="
if ! meson setup build "${common[@]}" -Dmicrosoft-clc="$MICROSOFT_CLC"; then
  echo "Configure failed with microsoft-clc=$MICROSOFT_CLC; retrying with microsoft-clc=disabled"
  rm -rf build
  meson setup build "${common[@]}" -Dmicrosoft-clc=disabled
fi

echo "== Building + installing to $PREFIX =="
ninja -C build -j"$(nproc)"
sudo ninja -C build install

ICD="$(find "$PREFIX" -name 'dzn_icd*.json' | head -n1 || true)"
[ -n "$ICD" ] || { echo "ERROR: build finished but no dzn ICD json found under $PREFIX"; exit 1; }
echo
echo "Built dzn. ICD: $ICD"
echo "Now run ./01-setup-wsl-vulkan.sh again (it will pick this up)."