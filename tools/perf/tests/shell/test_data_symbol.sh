#!/bin/bash
# Test data symbol (exclusive)

# SPDX-License-Identifier: GPL-2.0
# Leo Yan <leo.yan@linaro.org>, 2022

shelldir=$(dirname "$0")
# shellcheck source=lib/waiting.sh
. "${shelldir}"/lib/waiting.sh

# shellcheck source=lib/perf_has_symbol.sh
. "${shelldir}"/lib/perf_has_symbol.sh

skip_if_no_mem_event() {
	perf mem record -e list 2>&1 | grep -E -q 'available' && return 0
	return 2
}

skip_if_no_mem_event || exit 2

skip_test_missing_symbol workload_datasym_buf1

TEST_PROGRAM="perf test -w datasym"
PERF_DATA=$(mktemp /tmp/__perf_test.perf.data.XXXXX)
ERR_FILE=$(mktemp /tmp/__perf_test.stderr.XXXXX)

check_result() {
	# The memory report format is as below:
	#    99.92%  ...  [.] workload_datasym_buf1+0x38
	result=$(perf mem report -i ${PERF_DATA} -s symbol_daddr -q 2>&1 |
		 awk '/workload_datasym_buf1/ { print $4 }')

	# Testing is failed if has no any sample for "workload_datasym_buf1"
	[ -z "$result" ] && return 1

	while IFS= read -r line; do
		# The "data1" and "data2" fields in structure
		# "workload_datasym_buf1" have offset "0x0" and "0x38", returns
		# failure if detect any other offset value.
		if [ "$line" != "workload_datasym_buf1+0x0" ] && \
		   [ "$line" != "workload_datasym_buf1+0x38" ]; then
			return 1
		fi
	done <<< "$result"

	return 0
}

cleanup_files()
{
	echo "Cleaning up files..."
	rm -f ${PERF_DATA}
}

trap cleanup_files exit term int

echo "Recording workload..."

# perf mem/c2c internally uses IBS PMU on AMD CPU which doesn't support
# user/kernel filtering and per-process monitoring, spin program on
# specific CPU and test in per-CPU mode.
is_amd=$(grep -E -c 'vendor_id.*AuthenticAMD' /proc/cpuinfo)
if (($is_amd >= 1)); then
	perf mem record -vvv -o ${PERF_DATA} -C 0 -- taskset -c 0 $TEST_PROGRAM 2>"${ERR_FILE}" &
else
	perf mem record -vvv --all-user -o ${PERF_DATA} -- $TEST_PROGRAM 2>"${ERR_FILE}" &
fi

PERFPID=$!

wait_for_perf_to_start ${PERFPID} "${ERR_FILE}"

sleep 1

kill $PERFPID
wait $PERFPID

check_result
exit $?
