#!/usr/bin/env bash
# Debian 13 (trixie) on WSL2: Vulkan on AMD via Mesa "dzn" (Vulkan -> D3D12 -> Windows AMD driver)
# Env: BUILD_MESA=1 builds dzn from source automatically if the distro package lacks it.
#      MESA_PREFIX (default /opt/mesa-dzn) is where a source-built dzn is looked for.
set -euo pipefail
cd "$(dirname "$0")"
PREFIX="${MESA_PREFIX:-/opt/mesa-dzn}"
 
if [ ! -e /dev/dxg ]; then
  echo "ERROR: /dev/dxg not found. WSL2 GPU passthrough is not active."
  echo "Fix: install the AMD Adrenalin driver on Windows, run 'wsl --update', then 'wsl --shutdown'."
  exit 1
fi
 
echo "== Installing packages =="
sudo apt-get update
sudo apt-get install -y mesa-vulkan-drivers libvulkan1 vulkan-tools mesa-utils
 
echo "== Making sure WSL GPU libs (libd3d12, libdxcore) are on the loader path =="
if [ -d /usr/lib/wsl/lib ]; then
  echo "/usr/lib/wsl/lib" | sudo tee /etc/ld.so.conf.d/ld.wsl.conf >/dev/null
  sudo ldconfig
else
  echo "WARNING: /usr/lib/wsl/lib missing (Windows driver/WSL not up to date)."
fi
 
find_icd() {
  ls /usr/share/vulkan/icd.d/dzn_icd.*.json 2>/dev/null | head -n1 || true
  find "$PREFIX" -name 'dzn_icd*.json' 2>/dev/null | head -n1 || true
}
 
echo "== Locating dzn ICD =="
ICD="$(find_icd | head -n1)"
if [ -z "$ICD" ]; then
  echo "dzn ICD not found in /usr/share/vulkan/icd.d/ or $PREFIX."
  if [ "${BUILD_MESA:-0}" = "1" ]; then
    ./01b-build-mesa-dzn.sh
    ICD="$(find_icd | head -n1)"
  else
    echo "Debian's Mesa package lacks dzn. Build it from source with:"
    echo "  ./01b-build-mesa-dzn.sh        (then re-run this script)"
    exit 1
  fi
fi
[ -n "$ICD" ] || { echo "ERROR: still no dzn ICD."; exit 1; }
echo "Found: $ICD"
 
# If dzn came from the source build, make its lib dir loadable too
EXTRA_LD=""
if [[ "$ICD" == "$PREFIX"* ]]; then
  LIBDIR="$(dirname "$(find "$PREFIX" -name 'libvulkan_dzn.so' | head -n1)")"
  EXTRA_LD="$LIBDIR:"
fi
 
echo "== Writing /etc/profile.d/wsl-vulkan.sh =="
# Pin to dzn so llama.cpp doesn't also see the llvmpipe CPU device
sudo tee /etc/profile.d/wsl-vulkan.sh >/dev/null <<EOT
export VK_ICD_FILENAMES=$ICD
export LD_LIBRARY_PATH=${EXTRA_LD}/usr/lib/wsl/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
EOT
 
echo
echo "Done. Run: source /etc/profile.d/wsl-vulkan.sh && ./02-verify-vulkan.sh"
 