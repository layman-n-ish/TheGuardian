#! /usr/bin/env bash

if [ "$#" -lt 1 ]; then
	echo "Incorrect number of parameters"
	echo "Usage: ./run_mitigation_tests.sh [LEVEL]"
        echo -e "\nLEVEL: 'b' for build, 'r' for run, 'a' for both build and run"
	exit 1
fi

LVL="$1"
N_CORES=2
N_WARMUP_INSTR=1 # per million
N_SIM_INSTR=10 # per million
N_LLC_SETS=2048 # per CPU
N_LLC_WAYS=32

# modify LLC configurations
sed -i -e "s/#define LLC_SET NUM_CPUS\*2048/#define LLC_SET NUM_CPUS\*$N_LLC_SETS/g" inc/cache.h
sed -i -e "s/#define LLC_WAY 16/#define LLC_WAY $N_LLC_WAYS/g" inc/cache.h

LLC_REPL_DIR="./replacement"
BIN_DIR="./bin"
TRACES_DIR="./dpc3_traces"
RESULTS_DIR="./results_${N_CORES}core_${N_SIM_INSTR}M"
BENCHMARKS_DIR="./benchmarks"

# i=0
# for traces_path in "$TRACES_DIR"/*.trace.xz; do
#         temp=$(echo $traces_path | cut -d/ -f3)
#         TRACE_${i}="$temp"
#         ((i++))
# done

TRACE_0=bwaves_98B.trace.xz
TRACE_1=gamess_196B.trace.xz
TRACE_2=gcc_39B.trace.xz
TRACE_3=libquantum_964B.trace.xz

if [ $LVL == 'b' ] || [ $LVL == 'a' ]; then
        for llc_repl_path in "$LLC_REPL_DIR"/*.llc_repl; do
                llc_repl=$(echo $llc_repl_path | cut -d/ -f3 | cut -d. -f1)
                echo "Building ChampSim with $llc_repl as the LLC replacement policy..."
                ./build_champsim.sh bimodal no no no no $llc_repl $N_CORES > /dev/null 2>&1
        done
fi

echo;
rm -rf results_*

if [ $LVL == 'r' ] || [ $LVL == 'a' ]; then
        for bin_path in "$BIN_DIR"/*; do
                bin=$(echo $bin_path | cut -d/ -f3)
                echo "Running $bin binary..."
                if [ $N_CORES -eq 2 ]; then
                        ./run_2core.sh $bin $N_WARMUP_INSTR $N_SIM_INSTR 0 $TRACE_1 $TRACE_2
                else
                        ./run_4core.sh $bin $N_WARMUP_INSTR $N_SIM_INSTR 0 $TRACE_0 $TRACE_1 $TRACE_2 $TRACE_3
                fi
        done

        if [ ! -d $BENCHMARKS_DIR ]; then
                echo "Making $BENCHMARKS_DIR directory..."
                mkdir $BENCHMARKS_DIR
        fi

        for results_path in "$RESULTS_DIR"/*; do
                attrs=$(echo $results_path | cut -d/ -f3 | cut -d- -f7,8 | cut -d. -f1)
                out_file="${attrs}-${N_SIM_INSTR}M-${N_LLC_SETS}sets-${N_LLC_WAYS}ways"
                sed -n -e '1,12p' -e '/Total Simulation Statistics/, /Region of Interest Statistics/ p' $results_path > ${BENCHMARKS_DIR}/${out_file}
        done
fi

# restore modified LLC configurations for next run
sed -i -e "s/#define LLC_SET NUM_CPUS\*$N_LLC_SETS/#define LLC_SET NUM_CPUS\*2048/g" inc/cache.h
sed -i -e "s/#define LLC_WAY $N_LLC_WAYS/#define LLC_WAY 16/g" inc/cache.h
