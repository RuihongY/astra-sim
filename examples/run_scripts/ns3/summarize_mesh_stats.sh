#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
ASTRA_SIM_DIR="${SCRIPT_DIR:?}"/../../..
OUT_DIR_DEFAULT="${ASTRA_SIM_DIR:?}"/extern/network_backend/ns-3/scratch/output
OUT_DIR="${1:-$OUT_DIR_DEFAULT}"

FCT_FILE="${OUT_DIR}/fct.txt"
PFC_FILE="${OUT_DIR}/pfc.txt"
QLEN_FILE="${OUT_DIR}/qlen.txt"
TRACE_FILE="${OUT_DIR}/mix.tr"

if [[ ! -f "${FCT_FILE}" ]]; then
  echo "Missing ${FCT_FILE}"
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

awk 'NF>=8 {print $7}' "${FCT_FILE}" | sort -n > "${tmpdir}/fct_ns.sorted"
count=$(wc -l < "${tmpdir}/fct_ns.sorted")
if [[ "${count}" -eq 0 ]]; then
  echo "No completed flows in ${FCT_FILE}"
  exit 1
fi

p50_idx=$(( (count + 1) / 2 ))
p95_idx=$(( (95 * count + 99) / 100 ))
p99_idx=$(( (99 * count + 99) / 100 ))

p50=$(awk -v k="${p50_idx}" 'NR==k {print; exit}' "${tmpdir}/fct_ns.sorted")
p95=$(awk -v k="${p95_idx}" 'NR==k {print; exit}' "${tmpdir}/fct_ns.sorted")
p99=$(awk -v k="${p99_idx}" 'NR==k {print; exit}' "${tmpdir}/fct_ns.sorted")

read -r total_bytes avg_fct_ns avg_slowdown min_start_ns max_end_ns <<EOF
$(awk '
NF>=8 {
  size=$5+0;
  start=$6+0;
  fct=$7+0;
  standalone=$8+0;
  bytes+=size;
  sum_fct+=fct;
  if (standalone>0) sum_slow+=(fct/standalone);
  if (n==0 || start<min_start) min_start=start;
  end=start+fct;
  if (n==0 || end>max_end) max_end=end;
  n++;
}
END{
  if (n==0) {print "0 0 0 0 0"; exit}
  printf "%.0f %.3f %.4f %.0f %.0f", bytes, sum_fct/n, sum_slow/n, min_start, max_end;
}' "${FCT_FILE}")
EOF

sim_span_ns=$(( max_end_ns - min_start_ns ))
if [[ "${sim_span_ns}" -gt 0 ]]; then
  agg_bw_gbps=$(awk -v b="${total_bytes}" -v ns="${sim_span_ns}" 'BEGIN{printf "%.3f", (8.0*b)/ns}')
  agg_bw_gBs=$(awk -v b="${total_bytes}" -v ns="${sim_span_ns}" 'BEGIN{printf "%.3f", b/ns}')
else
  agg_bw_gbps="0.000"
  agg_bw_gBs="0.000"
fi

pfc_events=0
if [[ -f "${PFC_FILE}" ]]; then
  pfc_events=$(wc -l < "${PFC_FILE}")
fi

read -r qlen_samples qlen_avg_bytes qlen_max_bytes <<EOF
$(if [[ -f "${QLEN_FILE}" ]]; then
  awk '
  {
    for (i=1; i<=NF; i++) {
      if ($i=="j" && i+2<=NF) {
        v=$(i+2)+0;
        sum+=v;
        if (v>mx) mx=v;
        c++;
      }
    }
  }
  END{
    if (c==0) printf "0 0.0 0";
    else printf "%d %.1f %d", c, sum/c, mx;
  }' "${QLEN_FILE}"
else
  echo "0 0.0 0"
fi)
EOF

trace_size_bytes=0
if [[ -f "${TRACE_FILE}" ]]; then
  trace_size_bytes=$(wc -c < "${TRACE_FILE}")
fi

echo "NS3 Traffic Summary"
echo "output_dir: ${OUT_DIR}"
echo "flows_completed: ${count}"
echo "total_payload_bytes: ${total_bytes}"
echo "fct_avg_ns: ${avg_fct_ns}"
echo "fct_p50_ns: ${p50}"
echo "fct_p95_ns: ${p95}"
echo "fct_p99_ns: ${p99}"
echo "slowdown_avg(fct/standalone): ${avg_slowdown}"
echo "active_window_ns: ${sim_span_ns}"
echo "agg_throughput_Gbps: ${agg_bw_gbps}"
echo "agg_throughput_GBps: ${agg_bw_gBs}"
echo "pfc_events: ${pfc_events}"
echo "qlen_samples: ${qlen_samples}"
echo "qlen_avg_bytes: ${qlen_avg_bytes}"
echo "qlen_max_bytes: ${qlen_max_bytes}"
echo "mix.tr_size_bytes: ${trace_size_bytes}"
