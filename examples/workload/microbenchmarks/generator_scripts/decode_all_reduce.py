## ******************************************************************************
## This source code is licensed under the MIT license found in the
## LICENSE file in the root directory of this source tree.
##
## Copyright (c) 2024 Georgia Institute of Technology
## ******************************************************************************

import argparse
import os

from extern.graph_frontend.chakra.schema.protobuf.et_def_pb2 import (
    ALL_REDUCE,
    COMM_COLL_NODE,
    GlobalMetadata,
)
from extern.graph_frontend.chakra.schema.protobuf.et_def_pb2 import (
    AttributeProto as ChakraAttr,
)
from extern.graph_frontend.chakra.schema.protobuf.et_def_pb2 import Node as ChakraNode
from extern.graph_frontend.chakra.src.third_party.utils.protolib import (
    encodeMessage as encode_message,
)


def generate_decode_all_reduce(npus_count: int, coll_size_kb: int, num_reqs: int, path: str = "./") -> None:
    """
    Generate decode-like all-reduce ET files:
    - small message size (KB-scale)
    - many independent requests (no deps), mimicking continuous batching bursts.
    """
    coll_name = "decode_all_reduce"
    et_path = os.path.join(path, coll_name, f"{npus_count}npus_{coll_size_kb}KB_{num_reqs}req")
    os.makedirs(et_path, exist_ok=True)

    coll_size_bytes = coll_size_kb * 1024

    for npu in range(npus_count):
        et_filename = os.path.join(et_path, f"{coll_name}.{npu}.et")
        with open(et_filename, "wb") as et:
            encode_message(et, GlobalMetadata(version="0.0.4"))

            # Independent collective nodes (no dependency edges) create many ready requests.
            for req_id in range(num_reqs):
                node = ChakraNode()
                node.id = req_id
                node.name = f"{coll_name}_{npus_count}npus_{coll_size_kb}KB_req{req_id}"
                node.type = COMM_COLL_NODE
                node.attr.append(ChakraAttr(name="is_cpu_op", bool_val=False))
                node.attr.append(ChakraAttr(name="comm_type", int64_val=ALL_REDUCE))
                node.attr.append(ChakraAttr(name="comm_size", int64_val=coll_size_bytes))
                encode_message(et, node)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--npus-count", type=int, required=True)
    parser.add_argument("--coll-size-kb", type=int, required=True)
    parser.add_argument("--num-reqs", type=int, required=True)
    parser.add_argument("--path", type=str, default="./examples/workload/microbenchmarks")
    args = parser.parse_args()

    assert args.npus_count > 0
    assert args.coll_size_kb > 0
    assert args.num_reqs > 0

    generate_decode_all_reduce(
        npus_count=args.npus_count,
        coll_size_kb=args.coll_size_kb,
        num_reqs=args.num_reqs,
        path=args.path,
    )


if __name__ == "__main__":
    main()
