#!/bin/bash

USER_NAME=<your username>
USER_EMAIL=<your e-mail address>
USER_DESC="test-name-goes-here"
CLIENT=<host to run on (ie. localhost)>
SCENARIOS="read write randread randwrite mixed"
ENGINES="libaio sync"
IODEPTH="1,4,8,12,16,20"
BLOCK_SIZE="4k,8k,16k,32k,64k,128k,256k"
SAMPLES=5
TARGET_TYPE="device"
TARGETS="/dev/nvme0n1 /dev/nvme1n1"
#TARGET_TYPE="filesystem"
#TARGETS="/mnt/nvme0n1 /mnt/nvme1n1"

. /opt/pbench-agent/base

function notify() {
    if which ntfy > /dev/null 2>&1; then
	ntfy "$@"
    fi
}

JOB_FILE=/tmp/fio.job
MIXED_JOB_FILE=/tmp/fio.mix.job

cat <<EOF > ${JOB_FILE}
[global]
norandommap
time_based=1
runtime=20
ramp_time=5
size=10g
clocksource=gettimeofday
iodepth_batch_complete_min=1
iodepth_batch_submit=0

EOF

cat <<EOF > ${MIXED_JOB_FILE}
[global]
norandommap
time_based=1
runtime=20
ramp_time=5
size=10g
clocksource=gettimeofday
iodepth_batch_complete_min=1
iodepth_batch_submit=0
rwmixread=60
rwmixwrite=40
percentage_random=100,80

EOF

case "${TARGET_TYPE}" in
    "device")
	for TARGET in ${TARGETS}; do
	    echo "[job-${TARGET}]" >> ${JOB_FILE}
	    echo "filename=${TARGET}" >> ${JOB_FILE}

	    echo "[job-${TARGET}]" >> ${MIXED_JOB_FILE}
	    echo "filename=${TARGET}" >> ${MIXED_JOB_FILE}
	done
	;;
    "filesystem")
	for TARGET in ${TARGETS}; do
	    echo "[job-${TARGET}]" >> ${JOB_FILE}
	    echo "directory=${TARGET}" >> ${JOB_FILE}
	    echo "filename=fio.test.file" >> ${JOB_FILE}

	    echo "[job-${TARGET}]" >> ${MIXED_JOB_FILE}
	    echo "directory=${TARGET}" >> ${MIXED_JOB_FILE}
	    echo "filename=fio.test.file" >> ${MIXED_JOB_FILE}
	done
	;;
esac

for ENGINE in ${ENGINES}; do
    case "${ENGINE}" in
	"libaio")
	    PREFIX=${USER_DESC}-libaio
	    for SCENARIO in ${SCENARIOS}; do
		RUN_DESC=${USER_DESC}-${SCENARIO}-libaio

		case "${SCENARIO}" in
		    "read"|"write"|"randread"|"randwrite")
			pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --clients=${CLIENT} --rw=[rw] --bs=[bs] --ioengine=libaio \
					     --direct=1 --sync=0 --iodepth=[iodepth] --jobfile=${JOB_FILE} --iodepth_batch_complete_max=[iodepth] --[rw]=${SCENARIO} \
					     --[iodepth]=${IODEPTH} --[bs]=${BLOCK_SIZE} --samples=${SAMPLES}
			RET_VAL=$?
			;;
		    "mixed")
			pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --clients=${CLIENT} --rw=randrw --bs=[bs] --ioengine=libaio \
					     --direct=1 --sync=0 --iodepth=[iodepth] --jobfile=${MIXED_JOB_FILE} --iodepth_batch_complete_max=[iodepth] \
					     --[iodepth]=${IODEPTH} --[bs]=${BLOCK_SIZE} --samples=${SAMPLES}
			RET_VAL=$?
			;;
		esac

		if [ "${RET_VAL}" != "0" ]; then
		    notify -t "libaio run failed" -l INFO send "${RUN_DESC} - return code:${RET_VAL}"
		    exit 1
		else
		    notify -t "libaio run succeeded" -l INFO send "${RUN_DESC}"
		fi

		if pbench-move-results --user ${USER_EMAIL} --prefix ${PREFIX}; then
		    notify -t "move-results succeeded" -l INFO send "${RUN_DESC}"
		    pbench-clear-results
		else
		    notify -t "move-results failed" -l CRITICAL send "${RUN_DESC}"
		    exit 1
		fi
	    done
	    ;;
	"sync")
	    PREFIX=${USER_DESC}-sync
	    for SCENARIO in ${SCENARIOS}; do
		RUN_DESC=${USER_DESC}-${SCENARIO}-sync

		case "${SCENARIO}" in
		    "read"|"write"|"randread"|"randwrite")
			pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --clients=${CLIENT} --rw=[rw] --bs=[bs] --ioengine=sync \
					     --direct=1 --sync=0 --numjobs=[iodepth] --jobfile=${JOB_FILE} --[rw]=${SCENARIO} --[iodepth]=${IODEPTH} \
					     --[bs]=${BLOCK_SIZE} --samples=${SAMPLES}
			RET_VAL=$?
			;;
		    "mixed")
			pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --clients=${CLIENT} --rw=randrw --bs=[bs] --ioengine=sync \
					     --direct=1 --sync=0 --numjobs=[iodepth] --jobfile=${MIXED_JOB_FILE} --[iodepth]=${IODEPTH} \
					     --[bs]=${BLOCK_SIZE} --samples=${SAMPLES}
			RET_VAL=$?
			;;
		esac

		if [ "${RET_VAL}" != "0" ]; then
		    notify -t "sync run failed" -l INFO send "${RUN_DESC} - return code:${RET_VAL}"
		    exit 1
		else
		    notify -t "sync run succeeded" -l INFO send "${RUN_DESC}"
		fi

		if pbench-move-results --user ${USER_EMAIL} --prefix ${PREFIX}; then
		    notify -t "move-results succeeded" -l INFO send "${RUN_DESC}"
		    pbench-clear-results
		else
		    notify -t "move-results failed" -l CRITICAL send "${RUN_DESC}"
		    exit 1
		fi
	    done
	    ;;
    esac
done