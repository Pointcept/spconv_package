#!/bin/bash
# Parameterized cumm wheel builder
# Accepts CUMM_PYTHON_LIST env var (e.g., "3.10;3.11;3.12;3.13")
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

export CUMM_DISABLE_JIT="1"
export CUMM_CUDA_ARCH_LIST="all"

# Default to 3.10-3.13 if not specified
CUMM_PYTHON_LIST="${CUMM_PYTHON_LIST:-3.10;3.11;3.12;3.13}"

# Clean up previous build artifacts (may be owned by root from prior Docker runs)
rm -rf /io/build /io/*.egg-info /io/wheelhouse_tmp
mkdir -p /io/wheelhouse_tmp /io/dist

for PYVER in ${CUMM_PYTHON_LIST//;/ }; do
    PYVER2=$(echo "$PYVER" | sed 's/\.//')
    PYVER_CP="cp${PYVER2}-cp${PYVER2}"
    PYTHON="/opt/python/${PYVER_CP}/bin/python"

    echo "=== Building cumm for Python ${PYVER} ==="
    "${PYTHON}" -m pip install pccm pybind11 ccimport
    "/opt/python/${PYVER_CP}/bin/pip" wheel /io/ --no-deps -w /io/wheelhouse_tmp
done

# Bundle external shared libraries into the wheels
for whl in /io/wheelhouse_tmp/*.whl; do
    repair_wheel "$whl" /io/dist
done

rm -rf /io/wheelhouse_tmp
echo "=== cumm wheels built successfully ==="
ls -la /io/dist/
