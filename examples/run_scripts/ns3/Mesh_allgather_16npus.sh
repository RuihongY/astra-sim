#!/bin/bash
set -e
set -x

SCRIPT_DIR=$(dirname "$(realpath "$0")")
ASTRA_SIM_DIR="${SCRIPT_DIR:?}"/../../..
EXAMPLES_DIR="${ASTRA_SIM_DIR:?}"/examples
NS3_DIR="${ASTRA_SIM_DIR:?}"/extern/network_backend/ns-3

# Decode-like workload controls:
#   DECODE_MSG_KB: 32 or 64 (default: 64)
#   DECODE_REQS: number of concurrent all-reduce requests (default: 256)
DECODE_MSG_KB="${DECODE_MSG_KB:-64}"
DECODE_REQS="${DECODE_REQS:-256}"
WORKLOAD_DIR="${EXAMPLES_DIR:?}"/workload/microbenchmarks/decode_all_reduce
WORKLOAD_TAG="16npus_${DECODE_MSG_KB}KB_${DECODE_REQS}req"
WORKLOAD="${WORKLOAD_DIR:?}/${WORKLOAD_TAG}/decode_all_reduce"
SYSTEM="${EXAMPLES_DIR:?}"/system/native_collectives/Ring_4chunks.json
NETWORK="${NS3_DIR:?}"/scratch/config/config_mesh_16nodes.txt
LOGICAL_TOPOLOGY="${EXAMPLES_DIR:?}"/network/ns3/sample_16nodes_2D_4x4.json

MEMORY="${EXAMPLES_DIR:?}"/remote_memory/analytical/no_memory_expansion.json
COMM_GROUP_CONFIGURATION="empty"
NS3_BIN="${NS3_DIR:?}"/build/scratch/ns3.42-AstraSimNetwork-default
FLOW_FILE="${NS3_DIR:?}"/scratch/output/flow.txt
TRACE_FILE="${NS3_DIR:?}"/scratch/output/trace.txt

if [[ ! -x "${NS3_BIN}" ]]; then
    echo "[ASTRA-sim] ns-3 binary not found. Building AstraSimNetwork with MPI..."
    env -u LD_LIBRARY_PATH "${ASTRA_SIM_DIR:?}"/build/astra_ns3/build.sh
fi

# Generate decode-style workload traces if missing.
if [[ ! -f "${WORKLOAD}.0.et" ]]; then
    echo "[ASTRA-sim] Generating decode workload (${DECODE_MSG_KB}KB, ${DECODE_REQS} reqs, 16 NPUs)..."
    cd "${ASTRA_SIM_DIR:?}"
    python3 "${EXAMPLES_DIR:?}"/workload/microbenchmarks/generator_scripts/decode_all_reduce.py \
        --npus-count 16 \
        --coll-size-kb "${DECODE_MSG_KB}" \
        --num-reqs "${DECODE_REQS}"
fi

# ns-3 startup requires these files to exist.
mkdir -p "${NS3_DIR:?}"/scratch/output
if [[ ! -f "${FLOW_FILE}" ]]; then
    echo "0" > "${FLOW_FILE}"
fi
if [[ ! -f "${TRACE_FILE}" ]]; then
    echo "0" > "${TRACE_FILE}"
fi

cd "${NS3_DIR}/build/scratch"

echo "Running 16-NPU 2D-mesh decode simulation with WORKLOAD: ${WORKLOAD}"

"${NS3_BIN}" \
    --workload-configuration=${WORKLOAD} \
    --system-configuration=${SYSTEM} \
    --network-configuration=${NETWORK} \
    --remote-memory-configuration=${MEMORY} \
    --logical-topology-configuration=${LOGICAL_TOPOLOGY} \
    --comm-group-configuration=${COMM_GROUP_CONFIGURATION}

cd "${SCRIPT_DIR:?}"
