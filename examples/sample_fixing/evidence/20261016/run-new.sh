#!/bin/bash
set -eu
exec prlimit --as=8589934592:8589934592 timeout 600 env \
 JULIA_DEPOT_PATH=/tmp/qubo-finalize-DrOmiT/sample18/depot:/tmp/qubo-finalize-DrOmiT/sol-decomposition/depot:/tmp/qd013-general-install-2/depot:/home/bernalde/.julia \
 JULIA_LOAD_PATH=@:@stdlib JULIA_PKG_OFFLINE=true JULIA_PKG_PRECOMPILE_AUTO=0 \
 JULIA_NUM_PRECOMPILE_TASKS=1 JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 \
 JULIA_PYTHONCALL_EXE=/usr/bin/python3 \
 /home/bernalde/.julia/juliaup/julia-1.10.11+0.x64.linux.gnu/bin/julia \
 --startup-file=no --project=/tmp/qubo-finalize-DrOmiT/sample18/new-env "$@"
