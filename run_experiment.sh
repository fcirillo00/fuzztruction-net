EXPERIMENT_NAME="36h-3-full"

COVERAGE_PATH="/tmp/coverage"
PROFDATA_PATH="/home/user/fuzztruction/my-experiments/results/$EXPERIMENT_NAME/profdata"
TMP_PROFRAW_PATH="/tmp/profraw"

INTERVAL=60 #seconds
TIMEOUT=129600 # 36 hours

mkdir -p $COVERAGE_PATH
mkdir -p $PROFDATA_PATH
mkdir -p $TMP_PROFRAW_PATH

sudo ./target/debug/fuzztruction ./my-experiments/config/openvpn/openvpn.yml --log-output fuzz -j 1 -t ${TIMEOUT}s --log-level debug --purge &

sleep 2
for i in $(seq 0 $INTERVAL $TIMEOUT)
do
    sleep $INTERVAL
    mv $COVERAGE_PATH/id*.profraw $TMP_PROFRAW_PATH
    if [ "$(ls -A $TMP_PROFRAW_PATH/id*.profraw 2>/dev/null)" ]; then
        # only if files were moved
        llvm-profdata merge -sparse $TMP_PROFRAW_PATH/* -o $PROFDATA_PATH/$(date +%s).profdata
        rm -rf $TMP_PROFRAW_PATH/*
    fi

done

python3 /home/user/fuzztruction/compute_coverage.py $EXPERIMENT_NAME