# spconv_packages - Pre-built Wheels for spconv & cumm

## Overview

This repo builds pre-compiled wheels for [spconv](https://github.com/traveller59/spconv) (sparse convolution library) and its dependency [cumm](https://github.com/FindDefinition/cumm) (CUDA matrix multiply library). Both are forked under [Pointcept](https://github.com/Pointcept) since the originals are no longer maintained.

## Repository Structure

```
spconv_packages/
├── cumm/                  # Submodule: Pointcept/cumm (branch: main)
├── spconv/                # Submodule: Pointcept/spconv (branch: master)
├── build-all.sh           # Docker-based build orchestrator
├── tools/
│   └── build-local.sh     # Conda-based local build (no Docker)
├── envs/                  # Conda environment files (5 CUDA × 4 Python = 20)
├── docker/
│   ├── Dockerfile.cu124   # Custom image (CUDA 12.4 + GCC 13)
│   └── Dockerfile.cu130   # Custom image (CUDA 13.0)
└── dist/                  # Build output (gitignored)
    ├── cumm_cu{VER}/      # cumm wheels per CUDA version
    └── spconv_cu{VER}/    # spconv wheels per CUDA version
```

## Clone

```bash
git clone --recurse-submodules <this-repo-url>
cd spconv_packages
```

If you forgot `--recurse-submodules`:
```bash
git submodule update --init --recursive
```

## Build Matrix

| | Python 3.10 | Python 3.11 | Python 3.12 | Python 3.13 |
|---|:---:|:---:|:---:|:---:|
| **CUDA 11.8** | yes | yes | yes | yes |
| **CUDA 12.4** | yes | yes | yes | yes |
| **CUDA 12.6** | yes | yes | yes | yes |
| **CUDA 12.8** | yes | yes | yes | yes |
| **CUDA 13.0** | yes | yes | yes | yes |

## Two Build Methods

| Method | Tool | Produces | Best for |
|---|---|---|---|
| **Conda local** | `tools/build-local.sh` | 1 wheel per run (single Python) | Development, quick builds |
| **Docker batch** | `build-all.sh` | Multiple wheels (all Pythons) | CI, production manylinux wheels |

---

## Method 1: Conda Local Build (No Docker)

### Prerequisites

- [Conda](https://docs.conda.io/) or [Mamba](https://mamba.readthedocs.io/)
- Internet access (for conda packages and pip deps)

### Quick Start

```bash
# Build for CUDA 12.8, Python 3.10
bash tools/build-local.sh 12.8 3.10
```

This will:
1. Create/activate conda env `spconv-cu128` from `envs/cu128-py310.yml`
2. Build cumm wheel from `cumm/` submodule
3. Install cumm, then build spconv wheel from `spconv/` submodule
4. Output to `dist/cumm_cu128/` and `dist/spconv_cu128/`

### Build All Python Versions for One CUDA

```bash
for py in 3.10 3.11 3.12 3.13; do
    bash tools/build-local.sh 12.8 $py
done
```

### Conda Environment Files

Located in `envs/`, 20 files covering the full matrix. Each installs:
- CUDA toolkit (from `nvidia/label/cuda-X.X.X` channel)
- cuDNN (conda-forge)
- GCC/G++ 13.2 (conda-forge, required for CUDA < 13.0 compat)
- Python build deps via pip (pccm, pybind11, ccimport, etc.)

### Create a Custom Env Manually

```bash
conda env create -f envs/cu128-py312.yml
conda activate spconv-cu128-py312
```

---

## Method 2: Docker Batch Build

### Prerequisites

- Docker (tested with Docker Desktop 4.42 on WSL2)
- Internet access (to pull Docker images, download Boost, clone CCCL)

### Quick Build (all CUDA versions)

```bash
./build-all.sh all "3.10;3.11;3.12;3.13"
```

### Build a Single CUDA Version

```bash
./build-all.sh 128 "3.10;3.11;3.12;3.13"
```

The first argument is the CUDA version without dot (118, 124, 126, 128, 130).

### What build-all.sh Does

For each CUDA version:

1. **Selects Docker image**:
   - cu118: `scrin/manylinux2014-cuda:cu118-devel-1.0.0`
   - cu124: `manylinux-cuda:cu124-custom` (build from `docker/Dockerfile.cu124`)
   - cu126: `scrin/manylinux2014-cuda:cu126-devel-1.0.0`
   - cu128: `scrin/manylinux2014-cuda:cu128-devel-1.0.0`
   - cu130: `manylinux-cuda:cu130-custom` (build from `docker/Dockerfile.cu130`)

2. **Clones CCCL** (CUDA C++ Core Libraries) into `cumm/third_party/cccl/`:
   - CUDA < 12.0: CCCL v2.7.0
   - CUDA 12.x: CCCL v2.{minor}.0
   - CUDA 13.0+: skip (bundled in toolkit)

3. **Builds cumm wheels** via `cumm/tools/build-wheels-custom.sh`

4. **Downloads Boost 1.77.0** headers into `spconv/third_party/boost/` (first run only)

5. **Builds spconv wheels** via `spconv/tools/build-wheels-custom.sh`, mounting the cumm wheels for installation

6. **Collects wheels** into `dist/cumm_cu{VER}/` and `dist/spconv_cu{VER}/`

### Build Custom Docker Images (cu124, cu130)

These are needed because `scrin/` images don't exist for cu124 (pull issues) and cu130.

```bash
# CUDA 12.4 (needs GCC 13 - CUDA 12.4 doesn't support GCC 14+)
docker build --network host -t manylinux-cuda:cu124-custom -f docker/Dockerfile.cu124 docker/

# CUDA 13.0
docker build --network host -t manylinux-cuda:cu130-custom -f docker/Dockerfile.cu130 docker/
```

Both are based on `quay.io/pypa/manylinux_2_28_x86_64` with CUDA toolkit installed from NVIDIA's repo.

### Manual Build Steps (without build-all.sh)

#### Build cumm for a specific CUDA version (e.g., 12.8):

```bash
cd cumm
git clone --depth 1 https://github.com/NVIDIA/cccl.git third_party/cccl -b v2.8.0

docker run --rm \
  -e PLAT=manylinux_2_28_x86_64 \
  -e CUMM_CUDA_VERSION=12.8 \
  -e CUMM_PYTHON_LIST="3.10;3.11;3.12;3.13" \
  -v "$(pwd):/io" \
  scrin/manylinux2014-cuda:cu128-devel-1.0.0 \
  bash -c "source /etc/bashrc && /io/tools/build-wheels-custom.sh"
```

#### Build spconv (after cumm is built):

```bash
cd spconv
# Download Boost (first time only)
mkdir -p third_party
wget -L "https://archives.boost.io/release/1.77.0/source/boost_1_77_0.tar.gz" -O third_party/boost.tar.gz
tar xzf third_party/boost.tar.gz -C third_party/boost

docker run --rm \
  -e PLAT=manylinux_2_28_x86_64 \
  -e CUMM_CUDA_VERSION=12.8 \
  -e SPCONV_PYTHON_LIST="3.10;3.11;3.12;3.13" \
  -e BOOST_ROOT=/io/third_party/boost/boost_1_77_0 \
  -v "$(pwd):/io" \
  -v "/path/to/cumm/dist:/io/cumm_dist:ro" \
  scrin/manylinux2014-cuda:cu128-devel-1.0.0 \
  bash -c "source /etc/bashrc && /io/tools/build-wheels-custom.sh"
```

## Key Environment Variables

| Variable | Used by | Purpose |
|---|---|---|
| `CUMM_CUDA_VERSION` | both | CUDA version (e.g., `12.8`, `11.8`, `""` for CPU) |
| `CUMM_DISABLE_JIT` / `SPCONV_DISABLE_JIT` | cumm/spconv | Set to `"1"` for pre-compiled wheels |
| `CUMM_CUDA_ARCH_LIST` | both | GPU architectures (`"all"` for production) |
| `CUMM_PYTHON_LIST` / `SPCONV_PYTHON_LIST` | build scripts | Semicolon-separated Python versions |
| `BOOST_ROOT` | spconv | Path to Boost 1.77.0 headers |
| `PLAT` | auditwheel | Platform tag (`manylinux2014_x86_64` or `manylinux_2_28_x86_64`) |

## GPU Architecture Coverage

| CUDA Version | Architectures |
|---|---|
| 11.8 | sm_35 - sm_90 (Kepler through Hopper) |
| 12.4, 12.6 | sm_50 - sm_90 (Maxwell through Hopper) |
| 12.8 | sm_75 - sm_120 (Turing through Blackwell) |
| 13.0 | sm_75 - sm_120 (Turing through Blackwell) |

## Build Order

cumm must be built **before** spconv (spconv imports cumm at build time for kernel code generation).

## Dependency Chain

```
spconv -> cumm >= 0.8.2, < 0.9.0 (runtime + build-time)
cumm   -> pccm, pybind11, ccimport (build-time)
spconv -> pccm, pybind11, ccimport, Boost 1.77.0 (build-time)
cumm   -> CCCL (cloned into third_party/cccl during build, except CUDA 13.0+)
```

## Troubleshooting

- **Docker proxy issues**: If pulls fail, check `docker info | grep -i proxy`. Remove proxy from Docker Desktop settings if not needed.
- **GCC version mismatch**: CUDA 12.4 requires GCC <= 13. The custom Dockerfile installs `gcc-toolset-13`.
- **DNS failures in custom images**: Use `--network host` when running Docker containers.
- **Root-owned build artifacts**: Build scripts clean up with `rm -rf /io/build` inside Docker. If permissions block cleanup between builds, run a Docker container to remove them.
- **auditwheel tag variations**: Build scripts use `--only-plat` to produce clean single-tag wheel filenames.
