#!/bin/bash
# Parameterized spconv wheel builder
# Accepts SPCONV_PYTHON_LIST env var (e.g., "3.10;3.11;3.12;3.13")
# Expects cumm wheels at /cumm_dist/ for pre-installation
set -e -u -x

function repair_wheel {
    wheel="$1"
    outpath="$2"
    if ! auditwheel show "$wheel"; then
        echo "Skipping non-platform wheel $wheel"
    else
        auditwheel repair "$wheel" --plat "$PLAT" --only-plat -w "$outpath"
    fi
}

gcc -v
export SPCONV_DISABLE_JIT="1"
export CUMM_CUDA_ARCH_LIST="all"

# Default to 3.10-3.13 if not specified
SPCONV_PYTHON_LIST="${SPCONV_PYTHON_LIST:-3.10;3.11;3.12;3.13}"

# Derive CUDA version short string for wheel matching
CUDA_VER_SHORT=$(echo "${CUMM_CUDA_VERSION}" | sed 's/\.//')

# Clean up previous build artifacts (may be owned by root from prior Docker runs)
rm -rf /io/build /io/*.egg-info /io/wheelhouse_tmp
mkdir -p /io/wheelhouse_tmp /io/dist

for PYVER in ${SPCONV_PYTHON_LIST//;/ }; do
    PYVER2=$(echo "$PYVER" | sed 's/\.//')
    PYVER_CP="cp${PYVER2}-cp${PYVER2}"
    PYTHON="/opt/python/${PYVER_CP}/bin/python"
    PIP="/opt/python/${PYVER_CP}/bin/pip"

    echo "=== Building spconv for Python ${PYVER} ==="

    # Install build dependencies
    "${PIP}" install pccm pybind11 ccimport

    # Install pre-built cumm wheel
    if [ -d /cumm_dist ]; then
        CUMM_WHL=$(ls /cumm_dist/cumm_cu${CUDA_VER_SHORT}-*-${PYVER_CP}-*.whl 2>/dev/null | head -1)
        if [ -n "$CUMM_WHL" ]; then
            echo "Installing cumm from: ${CUMM_WHL}"
            "${PIP}" install "$CUMM_WHL"
        else
            echo "WARNING: No cumm wheel found for cu${CUDA_VER_SHORT} ${PYVER_CP}, trying pip install"
            "${PIP}" install "cumm-cu${CUDA_VER_SHORT}>=0.8.2"
        fi
    else
        echo "WARNING: /cumm_dist not found, trying pip install"
        "${PIP}" install "cumm-cu${CUDA_VER_SHORT}>=0.8.2"
    fi

    "${PIP}" wheel /io/ -v --no-deps -w /io/wheelhouse_tmp
done

# Bundle external shared libraries into the wheels
for whl in /io/wheelhouse_tmp/*.whl; do
    repair_wheel "$whl" /io/dist
done

rm -rf /io/wheelhouse_tmp
echo "=== spconv wheels built successfully ==="
ls -la /io/dist/
