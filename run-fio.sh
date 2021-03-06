#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; sh-indentation: 4; -*-

USER_NAME=<your username>
USER_EMAIL=<your e-mail address>
USER_DESC="test-name-goes-here"
USER_TAGS="${USER_DESC}"

CLIENT=<host to run on (ie. localhost)>

SCENARIOS="read write randread randwrite mixed"
ENGINES="libaio io_uring sync"
IODEPTHS="1,4,8,12,16,20"
BLOCK_SIZES="4k,8k,16k,32k,64k,128k,256k"
SAMPLES=3

TARGET_TYPE="device"
TARGETS[0]="/dev/nvme0n1"
TARGETS[1]="/dev/nvme1n1"
#TARGET_TYPE="filesystem"
#TARGETS[0]="/mnt/nvme0n1"
#TARGETS[1]="/mnt/nvme1n1"

UPLOAD="yes"
#UPLOAD="no"

DO_NOTIFY="yes"
#DO_NOTIFY="no"

MODE="run"
#MODE="test"

AIO_MULTIJOB="yes"
#AIO_MULTIJOB="no"

AIO_MULTIJOB_IOS_PER=4

USE_AFFINITY="no"
#USE_AFFINITY="yes"

#AFFINITY_TYPE="cpu"
AFFINITY_TYPE="numa"

#TARGET_AFFINITY[0]="0-3"
#TARGET_AFFINITY[1]="4-7"
TARGET_AFFINITY[0]="0"
TARGET_AFFINITY[1]="1"

DIRECT=1
RUNTIME=120

. /opt/pbench-agent/base

function notify() {
    if [ "${DO_NOTIFY}" == "yes" ]; then
        if which ntfy > /dev/null 2>&1; then
            ntfy "$@"
        fi
    fi
}

JOB_FILE=/tmp/run-fio.fio.job
MIXED_JOB_FILE=/tmp/run-fio.fio.mix.job
IO_URING_JOB_FILE=/tmp/run-fio.fio.io_uring.job
MIXED_IO_URING_JOB_FILE=/tmp/run-fio.fio.mix.io_uring.job

cat <<EOF > ${JOB_FILE}
[global]
norandommap
time_based=1
runtime=${RUNTIME}
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
runtime=${RUNTIME}
ramp_time=5
size=10g
clocksource=gettimeofday
iodepth_batch_complete_min=1
iodepth_batch_submit=0
rwmixread=60
rwmixwrite=40
percentage_random=100,80
EOF

cat <<EOF > ${IO_URING_JOB_FILE}
[global]
norandommap
time_based=1
runtime=${RUNTIME}
ramp_time=5
size=10g
clocksource=gettimeofday
iodepth_batch_complete_min=1
iodepth_batch_submit=0
hipri
fixedbufs
registerfiles
sqthread_poll=1
EOF

cat <<EOF > ${MIXED_IO_URING_JOB_FILE}
[global]
norandommap
time_based=1
runtime=${RUNTIME}
ramp_time=5
size=10g
clocksource=gettimeofday
iodepth_batch_complete_min=1
iodepth_batch_submit=0
hipri
fixedbufs
registerfiles
sqthread_poll=1
rwmixread=60
rwmixwrite=40
percentage_random=100,80
EOF

function create_affinity() {
    local index=$1
    local file=$2

    if [ "${USE_AFFINITY}" == "no" ]; then
        return
    fi

    if [ -z "${TARGET_AFFINITY[$i]}" ]; then
        return
    fi

    case "${AFFINITY_TYPE}" in
        "cpu")
            echo "cpus_allowed=${TARGET_AFFINITY[$i]}" >> ${file}
            echo "cpus_allowed_policy=shared" >> ${file}
            ;;
        "numa")
            echo "numa_cpu_nodes=${TARGET_AFFINITY[$i]}" >> ${file}
            echo "numa_mem_policy=local" >> ${file}
            ;;
    esac
}

function create_device_job() {
    local target=$1
    local file=$2

    echo >> ${file}
    echo "[job-${target}]" >> ${file}
    echo "filename=${target}" >> ${file}
}

function create_filesystem_job() {
    local target=$1
    local file=$2

    echo >> ${file}
    echo "[job-${target}]" >> ${file}
    echo "directory=${target}" >> ${file}
    echo "filename=fio.test.file" >> ${file}
}

case "${TARGET_TYPE}" in
    "device")
        for ((i=0; $i < ${#TARGETS[*]}; i++)); do
            create_device_job ${TARGETS[$i]} ${JOB_FILE}
            create_affinity $i ${JOB_FILE}

            create_device_job ${TARGETS[$i]} ${IO_URING_JOB_FILE}
            create_affinity $i ${IO_URING_JOB_FILE}

            create_device_job ${TARGETS[$i]} ${MIXED_JOB_FILE}
            create_affinity $i ${MIXED_JOB_FILE}

            create_device_job ${TARGETS[$i]} ${MIXED_IO_URING_JOB_FILE}
            create_affinity $i ${MIXED_IO_URING_JOB_FILE}
        done
        ;;
    "filesystem")
        for ((i=0; $i < ${#TARGETS[*]}; i++)); do
            create_device_job ${TARGETS[$i]} ${JOB_FILE}
            create_affinity $i ${JOB_FILE}

            create_device_job ${TARGETS[$i]} ${IO_URING_JOB_FILE}
            create_affinity $i ${IO_URING_JOB_FILE}

            create_device_job ${TARGETS[$i]} ${MIXED_JOB_FILE}
            create_affinity $i ${MIXED_JOB_FILE}

            create_device_job ${TARGETS[$i]} ${MIXED_IO_URING_JOB_FILE}
            create_affinity $i ${MIXED_IO_URING_JOB_FILE}
        done
        ;;
esac

for ENGINE in ${ENGINES}; do
    echo "ENGINE=${ENGINE}"

    case "${ENGINE}" in
        "libaio"|"io_uring")
            PREFIX=${USER_DESC}-${ENGINE}
            for SCENARIO in ${SCENARIOS}; do
                echo "SCENARIO=${SCENARIO}"

                RUN_DESC=${USER_DESC}-${SCENARIO}-${ENGINE}

                case "${SCENARIO}" in
                    "read"|"write"|"randread"|"randwrite")
                        case "${ENGINE}" in
                            "libaio")
                                CURRENT_JOB_FILE=${JOB_FILE}
                                ;;
                            "io_uring")
                                CURRENT_JOB_FILE=${IO_URING_JOB_FILE}
                                ;;
                        esac

                        case "${AIO_MULTIJOB}" in
                            "no")
                                param_sets="--rw=[rw] --bs=[bs] --ioengine=${ENGINE} --direct=${DIRECT} --sync=0 --iodepth=[iodepth] --jobfile=${CURRENT_JOB_FILE}"
                                param_sets+=" --iodepth_batch_complete_max=[iodepth] --[rw]=${SCENARIO} --[iodepth]=${IODEPTHS} --[bs]=${BLOCK_SIZES} --samples=${SAMPLES}"
                                ;;
                            "yes")
                                TMP_IODEPTHS=$(echo "${IODEPTHS}" | sed -e "s/,/ /g")
                                param_sets=""
                                for IODEPTH in ${TMP_IODEPTHS}; do
                                    JOBS=$(echo "${IODEPTH}/${AIO_MULTIJOB_IOS_PER}" | bc)
                                    if [ "${JOBS}" == "0" ]; then
                                        JOBS=1
                                    fi
                                    if [ "${JOBS}" -gt 1 ]; then
                                        IODEPTH=${AIO_MULTIJOB_IOS_PER}
                                    fi

                                    param_sets+=" --rw=[rw] --bs=[bs] --ioengine=${ENGINE} --direct=${DIRECT} --sync=0 --iodepth=${IODEPTH} --numjobs=${JOBS} --jobfile=${CURRENT_JOB_FILE}"
                                    param_sets+=" --iodepth_batch_complete_max=${IODEPTH} --[rw]=${SCENARIO} --[bs]=${BLOCK_SIZES} --samples=${SAMPLES}"
                                    param_sets+=" --"
                                done
                                ;;
                        esac

                        case "${MODE}" in
                            "run")
                                pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --user-tags=${USER_TAGS} --clients=${CLIENT} ${param_sets}
                                ;;
                            "test")
                                pbench-gen-iterations fio ${param_sets}
                                ;;
                        esac

                        RET_VAL=$?
                        ;;
                    "mixed")
                        case "${ENGINE}" in
                            "libaio")
                                CURRENT_JOB_FILE=${MIXED_JOB_FILE}
                                ;;
                            "io_uring")
                                CURRENT_JOB_FILE=${MIXED_IO_URING_JOB_FILE}
                                ;;
                        esac

                        case "${AIO_MULTIJOB}" in
                            "no")
                                param_sets="--rw=randrw --bs=[bs] --ioengine=${ENGINE} --direct=${DIRECT} --sync=0 --iodepth=[iodepth] --jobfile=${CURRENT_JOB_FILE}"
                                param_sets+=" --iodepth_batch_complete_max=[iodepth] --[iodepth]=${IODEPTHS} --[bs]=${BLOCK_SIZES} --samples=${SAMPLES}"
                                ;;
                            "yes")
                                TMP_IODEPTHS=$(echo "${IODEPTHS}" | sed -e "s/,/ /g")
                                param_sets=""
                                for IODEPTH in ${TMP_IODEPTHS}; do
                                    JOBS=$(echo "${IODEPTH}/${AIO_MULTIJOB_IOS_PER}" | bc)
                                    if [ "${JOBS}" == "0" ]; then
                                        JOBS=1
                                    fi
                                    if [ "${JOBS}" -gt 1 ]; then
                                        IODEPTH=${AIO_MULTIJOB_IOS_PER}
                                    fi

                                    param_sets+=" --rw=randrw --bs=[bs] --ioengine=${ENGINE} --direct=${DIRECT} --sync=0 --iodepth=${IODEPTH} --numjobs=${JOBS} --jobfile=${CURRENT_JOB_FILE}"
                                    param_sets+=" --iodepth_batch_complete_max=${IODEPTH} --[bs]=${BLOCK_SIZES} --samples=${SAMPLES}"
                                    param_sets+=" --"
                                done
                                ;;
                        esac

                        case "${MODE}" in
                            "run")
                                pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --user-tags=${USER_TAGS} --clients=${CLIENT} ${param_sets}
                                ;;
                            "test")
                                pbench-gen-iterations fio ${param_sets}
                                ;;
                        esac

                        RET_VAL=$?
                        ;;
                esac

                if [ "${MODE}" == "run" ]; then
                    if [ "${RET_VAL}" != "0" ]; then
                        notify -t "${ENGINE} run failed" -l INFO send "${RUN_DESC} - return code:${RET_VAL}"
                        exit 1
                    else
                        notify -t "${ENGINE} run succeeded" -l INFO send "${RUN_DESC}"
                    fi

                    if [ "${UPLOAD}" == "yes" ]; then
                        if pbench-move-results --user ${USER_EMAIL} --prefix ${PREFIX}; then
                            notify -t "move-results succeeded" -l INFO send "${RUN_DESC}"
                            pbench-clear-results
                        else
                            notify -t "move-results failed" -l CRITICAL send "${RUN_DESC}"
                            exit 1
                        fi
                    else
                        echo "Skipping pbench-move-results due to UPLOAD=${UPLOAD}"
                    fi
                fi
            done
            ;;
        "sync")
            PREFIX=${USER_DESC}-sync
            for SCENARIO in ${SCENARIOS}; do
                echo "SCENARIO=${SCENARIO}"

                RUN_DESC=${USER_DESC}-${SCENARIO}-sync

                case "${SCENARIO}" in
                    "read"|"write"|"randread"|"randwrite")
                        param_sets="--rw=[rw] --bs=[bs] --ioengine=sync --direct=${DIRECT} --sync=0 --numjobs=[iodepth] --jobfile=${JOB_FILE}"
                        param_sets+=" --[rw]=${SCENARIO} --[iodepth]=${IODEPTHS} --[bs]=${BLOCK_SIZES} --samples=${SAMPLES}"

                        case "${MODE}" in
                            "run")
                                pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --user-tags=${USER_TAGS} --clients=${CLIENT} ${param_sets}
                                ;;
                            "test")
                                pbench-gen-iterations fio ${param_sets}
                                ;;
                        esac

                        RET_VAL=$?
                        ;;
                    "mixed")
                        param_sets="--rw=randrw --bs=[bs] --ioengine=sync --direct=${DIRECT} --sync=0 --numjobs=[iodepth] --jobfile=${MIXED_JOB_FILE}"
                        param_sets+=" --[iodepth]=${IODEPTHS} --[bs]=${BLOCK_SIZES} --samples=${SAMPLES}"

                        case "${MODE}" in
                            "run")
                                pbench-run-benchmark fio --user-name=${USER_NAME} --user-email=${USER_EMAIL} --user-desc=${RUN_DESC} --user-tags=${USER_TAGS} --clients=${CLIENT} ${param_sets}
                                ;;
                            "test")
                                pbench-gen-iterations fio ${param_sets}
                                ;;
                        esac

                        RET_VAL=$?
                        ;;
                esac

                if [ "${MODE}" == "run" ]; then
                    if [ "${RET_VAL}" != "0" ]; then
                        notify -t "sync run failed" -l INFO send "${RUN_DESC} - return code:${RET_VAL}"
                        exit 1
                    else
                        notify -t "sync run succeeded" -l INFO send "${RUN_DESC}"
                    fi

                    if [ "${UPLOAD}" == "yes" ]; then
                        if pbench-move-results --user ${USER_EMAIL} --prefix ${PREFIX}; then
                            notify -t "move-results succeeded" -l INFO send "${RUN_DESC}"
                            pbench-clear-results
                        else
                            notify -t "move-results failed" -l CRITICAL send "${RUN_DESC}"
                            exit 1
                        fi
                    else
                        echo "Skipping pbench-move-results due to UPLOAD=${UPLOAD}"
                    fi
                fi
            done
            ;;
    esac
done
