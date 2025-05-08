#!/bin/bash

N=5  # Numero di iterazioni

for ((i=1; i<=N; i++)); do
    timeout 10m ./target/release/fuzztruction ./my-experiments/config/openvpn/openvpn.yml --log-output fuzz -j 1 -t 10m --purge --log-level info | tee ./eval-result/benchmark-result/${i}.txt
done
