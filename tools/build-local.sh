#!/bin/bash
# Local wheel build script using conda (no Docker required)
# Usage: bash tools/build-local.sh <cuda_version> <python_version>
# Example: bash tools/build-local.sh 12.8 3.10
#          bash tools/build-local.sh 13.0 3.12

set -e -u

CUDA_VERSION="${1:?Usage: $0 <cuda_version> <python_version>  (e.g. 12.8 3.10)}"
PYTHON_VERSION="${2:?Usage: $0 <cuda_version> <python_version>  (e.g. 12.8 3.10)}"

CUDA_SHORT=$(echo "$CUDA_VERSION" | tr -d '.')
PYTHON_SHORT=$(echo "$PYTHON_VERSION" | tr -d '.')

# Determine conda env name (py310 is default, no suffix)
if [ "$PYTHON_VERSION" = "3.10" ]; then
    ENV_NAME="spconv-cu${CUDA_SHORT}"
else
    ENV_NAME="spconv-cu${CUDA_SHORT}-py${PYTHON_SHORT}"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CUMM_DIR="${PROJECT_DIR}/cumm"
SPCONV_DIR="${PROJECT_DIR}/spconv"
DIST_DIR="${PROJECT_DIR}/dist/cumm_cu${CUDA_SHORT}"
SPCONV_DIST_DIR="${PROJECT_DIR}/dist/spconv_cu${CUDA_SHORT}"

echo "=== Build Configuration ==="
echo "CUDA version:   ${CUDA_VERSION} (cu${CUDA_SHORT})"
echo "Python version: ${PYTHON_VERSION} (py${PYTHON_SHORT})"
echo "Conda env:      ${ENV_NAME}"
echo "Project dir:    ${PROJECT_DIR}"
echo "Cumm dir:       ${CUMM_DIR}"
echo "Spconv dir:     ${SPCONV_DIR}"
echo "Output dirs:    ${DIST_DIR}, ${SPCONV_DIST_DIR}"
echo ""

# Check submodule directories exist
if [ ! -d "$CUMM_DIR" ]; then
    echo "ERROR: cumm directory not found at ${CUMM_DIR}"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi
if [ ! -d "$SPCONV_DIR" ]; then
    echo "ERROR: spconv directory not found at ${SPCONV_DIR}"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Check conda env exists, create if not
if ! conda env list | grep -q "^${ENV_NAME} "; then
    ENV_FILE="${PROJECT_DIR}/envs/cu${CUDA_SHORT}-py${PYTHON_SHORT}.yml"
    if [ -f "$ENV_FILE" ]; then
        echo "Creating conda env from ${ENV_FILE}..."
        conda env create -f "$ENV_FILE"
    else
        echo "ERROR: Conda env '${ENV_NAME}' not found and no env file at ${ENV_FILE}"
        exit 1
    fi
fi

# Activate conda env
eval "$(conda shell.bash hook)"
conda activate "$ENV_NAME"

# Install build dependencies
pip install "pccm>=0.4.16" "pybind11>=2.6.0" "ccimport>=0.4.4" fire numpy setuptools wheel 2>/dev/null

# Export build environment variables
export CUMM_CUDA_VERSION="$CUDA_VERSION"
export CUMM_DISABLE_JIT=1
export SPCONV_DISABLE_JIT=1
export CUMM_CUDA_ARCH_LIST="all"

mkdir -p "$DIST_DIR" "$SPCONV_DIST_DIR"

# Step 1: Build cumm wheel
echo ""
echo "=== Building cumm wheel (cu${CUDA_SHORT}, py${PYTHON_SHORT}) ==="
cd "$CUMM_DIR"
rm -rf build dist *.egg-info
python setup.py bdist_wheel
CUMM_WHEEL=$(ls dist/cumm_cu${CUDA_SHORT}-*.whl 2>/dev/null | head -1)
if [ -z "$CUMM_WHEEL" ]; then
    echo "ERROR: cumm wheel not found after build"
    exit 1
fi
cp "$CUMM_WHEEL" "$DIST_DIR/"
echo "Built: $(basename "$CUMM_WHEEL")"

# Step 2: Install cumm wheel
echo ""
echo "=== Installing cumm wheel ==="
pip install "$CUMM_WHEEL" --force-reinstall

# Step 3: Build spconv wheel
echo ""
echo "=== Building spconv wheel (cu${CUDA_SHORT}, py${PYTHON_SHORT}) ==="
cd "$SPCONV_DIR"
rm -rf build *.egg-info
python setup.py bdist_wheel
SPCONV_WHEEL=$(ls dist/spconv_cu${CUDA_SHORT}-*.whl 2>/dev/null | sort -t- -k3 | tail -1)
if [ -z "$SPCONV_WHEEL" ]; then
    echo "ERROR: spconv wheel not found after build"
    exit 1
fi
cp "$SPCONV_WHEEL" "$SPCONV_DIST_DIR/"
echo "Built: $(basename "$SPCONV_WHEEL")"

# Done
echo ""
echo "=== Build complete ==="
echo "Wheels:"
ls -lh "$DIST_DIR/"*cu${CUDA_SHORT}*cp${PYTHON_SHORT}* 2>/dev/null || true
ls -lh "$SPCONV_DIST_DIR/"*cu${CUDA_SHORT}*cp${PYTHON_SHORT}* 2>/dev/null || true
