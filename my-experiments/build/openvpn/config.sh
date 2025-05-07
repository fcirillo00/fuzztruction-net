#!/usr/bin/env bash

set -eu

function build_generator {
    rm -rf generator
    cp -r src generator

    pushd generator > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=call,branch,load,store,select,switch
    # export FT_HOOK_INS=branch,load,store,select,switch

    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++
    export CFLAGS="-g -O3 -DNDEBUG -D_FORTIFY_SOURCE=0 -DFT_FUZZING -DFT_GENERATOR"
    export CXXFLAGS="-g -O3 -DNDEBUG -D_FORTIFY_SOURCE=0 -DFT_FUZZING -DFT_GENERATOR"

    git apply ../diff_generator.patch

    autoreconf -i -v -f
    # enable-iproute2 required for no-root execution
    ./configure --disable-lz4 --enable-iproute2
    make -j12

    cp src/openvpn/openvpn openvpn
    # ensure that openvpn can attach to dev0
    sudo setcap cap_net_admin=eip openvpn

    popd > /dev/null
}

function build_consumer {
    rm -rf consumer
    cp -r src consumer

    pushd consumer > /dev/null
    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_CONSUMER"

    git apply ../diff_consumer.patch

    autoreconf -i -v -f
    # enable-iproute2 required for no-root execution
    ./configure --disable-lz4 --enable-iproute2
    make -j12

    cp src/openvpn/openvpn openvpn
    # ensure that openvpn can attach to dev0
    sudo setcap cap_net_admin=eip openvpn

    popd > /dev/null
}

function install_dependencies {
    sudo apt-get install -y pkg-config make autoconf automake libtool libssl-dev liblzo2-dev libpam-dev libnl-3-dev libnl-genl-3-dev libcap-ng-dev
}

function get_source {
    rm -rf src
    mkdir -p src
    pushd src > /dev/null
    
    # Clone the repository and checkout the specific branch
    git clone --branch release/2.6 --single-branch https://github.com/OpenVPN/openvpn.git .
    
    popd > /dev/null
}

function build_consumer_llvm_cov {
    echo "" > /dev/null
}
function build_consumer_afl_net {
    echo "" > /dev/null
}
function build_consumer_stateafl {
    echo "" > /dev/null
}
function build_consumer_sgfuzz {
    echo "" > /dev/null
}
# get_source
# # install_dependencies
# build_consumer
# build_generator