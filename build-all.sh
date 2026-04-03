#!/bin/bash
# Unified build orchestrator for cumm and spconv wheels
# Usage: ./build-all.sh [CUDA_VERSION] [PYTHON_LIST]
# Example: ./build-all.sh 128 "3.10;3.11;3.12;3.13"
# Example: ./build-all.sh all   (builds all CUDA versions)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CUMM_DIR="${SCRIPT_DIR}/cumm"
SPCONV_DIR="${SCRIPT_DIR}/spconv"
DIST_DIR="${SCRIPT_DIR}/dist"
DOCKER_DIR="${SCRIPT_DIR}/docker"

PYTHON_LIST="${2:-3.10;3.11;3.12;3.13}"

# All supported CUDA versions
ALL_CUDA_VERSIONS="118 124 126 128 130"

if [ "${1:-all}" = "all" ]; then
    CUDA_VERSIONS="$ALL_CUDA_VERSIONS"
else
    CUDA_VERSIONS="$1"
fi

# Map CUDA version to Docker image and platform tag
get_docker_image() {
    local cuda_ver="$1"
    case "$cuda_ver" in
        130) echo "manylinux-cuda:cu130-custom" ;;
        *)   echo "scrin/manylinux2014-cuda:cu${cuda_ver}-devel-1.0.0" ;;
    esac
}

get_plat_tag() {
    local cuda_ver="$1"
    if [ "$cuda_ver" -gt 123 ] 2>/dev/null; then
        echo "manylinux_2_28_x86_64"
    else
        echo "manylinux2014_x86_64"
    fi
}

get_cccl_branch() {
    local cuda_ver="$1"
    local major="${cuda_ver:0:2}"
    local minor="${cuda_ver:2}"
    # Only for 2-digit minor: 118 -> 11, 8; 124 -> 12, 4
    if [ ${#cuda_ver} -eq 3 ]; then
        major="${cuda_ver:0:2}"
        minor="${cuda_ver:2:1}"
    elif [ ${#cuda_ver} -eq 2 ]; then
        major="${cuda_ver:0:1}"
        minor="${cuda_ver:1:1}"
    fi

    if [ "$major" -ge 13 ]; then
        echo ""  # CUDA 13+ bundles CCCL
    elif [ "$major" -lt 12 ]; then
        echo "v2.7.0"
    elif [ "$major" -eq 12 ] && [ "$minor" -lt 2 ]; then
        echo "v2.2.0"
    else
        echo "v2.${minor}.0"
    fi
}

get_cuda_version_dotted() {
    local cuda_ver="$1"
    if [ ${#cuda_ver} -eq 3 ]; then
        echo "${cuda_ver:0:2}.${cuda_ver:2:1}"
    elif [ ${#cuda_ver} -eq 2 ]; then
        echo "${cuda_ver:0:1}.${cuda_ver:1:1}"
    else
        echo "$cuda_ver"
    fi
}

# Prepare output directory
mkdir -p "${DIST_DIR}"

# Download Boost headers if not present
if [ ! -d "${SPCONV_DIR}/third_party/boost/boost_1_77_0" ]; then
    echo "=== Downloading Boost 1.77.0 headers ==="
    mkdir -p "${SPCONV_DIR}/third_party"
    wget -q https://boostorg.jfrog.io/artifactory/main/release/1.77.0/source/boost_1_77_0.zip \
        -O "${SPCONV_DIR}/third_party/boost.zip"
    unzip -q "${SPCONV_DIR}/third_party/boost.zip" -d "${SPCONV_DIR}/third_party/boost"
    rm -f "${SPCONV_DIR}/third_party/boost.zip"
    echo "Boost downloaded to ${SPCONV_DIR}/third_party/boost/boost_1_77_0"
fi

# Build CUDA 13.0 Docker image if needed
if echo "$CUDA_VERSIONS" | grep -q "130"; then
    if ! docker image inspect manylinux-cuda:cu130-custom >/dev/null 2>&1; then
        echo "=== Building custom Docker image for CUDA 13.0 ==="
        docker build -t manylinux-cuda:cu130-custom -f "${DOCKER_DIR}/Dockerfile.cu130" "${DOCKER_DIR}"
    fi
fi

# Build for each CUDA version
for CUDA_VER in $CUDA_VERSIONS; do
    echo ""
    echo "================================================================"
    echo "=== Building wheels for CUDA ${CUDA_VER} ==="
    echo "================================================================"

    DOCKER_IMAGE=$(get_docker_image "$CUDA_VER")
    PLAT=$(get_plat_tag "$CUDA_VER")
    CCCL_BRANCH=$(get_cccl_branch "$CUDA_VER")
    CUDA_DOTTED=$(get_cuda_version_dotted "$CUDA_VER")

    # --- Build cumm ---
    echo "=== [${CUDA_VER}] Building cumm ==="

    # Clean previous build artifacts (use Docker to handle root-owned files)
    docker run --rm -v "${CUMM_DIR}:/io" "$DOCKER_IMAGE" \
        bash -c "rm -rf /io/build /io/dist /io/wheelhouse_tmp /io/*.egg-info" 2>/dev/null || true
    mkdir -p "${CUMM_DIR}/dist"
    rm -rf "${CUMM_DIR}/third_party/cccl"

    # Clone CCCL if needed
    if [ -n "$CCCL_BRANCH" ]; then
        echo "Cloning CCCL ${CCCL_BRANCH}..."
        git clone --depth 1 https://github.com/NVIDIA/cccl.git \
            "${CUMM_DIR}/third_party/cccl" -b "$CCCL_BRANCH"
    else
        echo "Skipping CCCL clone (bundled in CUDA ${CUDA_VER})"
    fi

    chmod +x "${CUMM_DIR}/tools/build-wheels-custom.sh"
    docker run --rm \
        -e PLAT="$PLAT" \
        -e CUMM_CUDA_VERSION="$CUDA_DOTTED" \
        -e CUMM_PYTHON_LIST="$PYTHON_LIST" \
        -v "${CUMM_DIR}:/io" \
        "$DOCKER_IMAGE" \
        bash -c "source /etc/bashrc 2>/dev/null; /io/tools/build-wheels-custom.sh"

    echo "=== [${CUDA_VER}] cumm wheels: ==="
    ls -la "${CUMM_DIR}/dist/"

    # --- Build spconv ---
    echo "=== [${CUDA_VER}] Building spconv ==="

    # Clean previous build artifacts (use Docker to handle root-owned files)
    docker run --rm -v "${SPCONV_DIR}:/io" "$DOCKER_IMAGE" \
        bash -c "rm -rf /io/build /io/dist /io/wheelhouse_tmp /io/*.egg-info" 2>/dev/null || true
    mkdir -p "${SPCONV_DIR}/dist"

    chmod +x "${SPCONV_DIR}/tools/build-wheels-custom.sh"
    docker run --rm \
        -e PLAT="$PLAT" \
        -e CUMM_CUDA_VERSION="$CUDA_DOTTED" \
        -e SPCONV_PYTHON_LIST="$PYTHON_LIST" \
        -e BOOST_ROOT="/io/third_party/boost/boost_1_77_0" \
        -v "${SPCONV_DIR}:/io" \
        -v "${DIST_DIR}/cumm_cu${CUDA_VER}:/io/cumm_dist:ro" \
        "$DOCKER_IMAGE" \
        bash -c "source /etc/bashrc 2>/dev/null; /io/tools/build-wheels-custom.sh"

    echo "=== [${CUDA_VER}] spconv wheels: ==="
    ls -la "${SPCONV_DIR}/dist/"

    # Save cumm wheels per CUDA version (to avoid overwriting when building next version)
    mkdir -p "${DIST_DIR}/cumm_cu${CUDA_VER}"
    cp "${CUMM_DIR}/dist/"*.whl "${DIST_DIR}/cumm_cu${CUDA_VER}/" 2>/dev/null || true

    # Collect all wheels to top-level dist
    cp "${CUMM_DIR}/dist/"*.whl "${DIST_DIR}/" 2>/dev/null || true
    cp "${SPCONV_DIR}/dist/"*.whl "${DIST_DIR}/" 2>/dev/null || true

    echo "=== [${CUDA_VER}] Done ==="
done

echo ""
echo "================================================================"
echo "=== All wheels collected in ${DIST_DIR} ==="
echo "================================================================"
ls -la "${DIST_DIR}/"
