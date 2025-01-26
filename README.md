# Quick start

```sh
git clone https://github.com/fcirillo00/fuzztruction-net.git && \
    cd fuzztruction-net && \
    git submodule update --init

./env/build.sh

./env/start.sh

# opens shell
./env/start.sh

### inside container 

# build openvpn
cd my-experiments/build
./build.sh openvpn src deps generator consumer
cd ../..

# initialize system for fuzzing openvpn
./init.sh

# quick test
sudo ./target/debug/fuzztruction ./my-experiments/config/openvpn/openvpn.yml --purge --log-output benchmark -i 5 --log-level trace

# fuzz (im not sure if it can be run as multi-process)
sudo ./target/debug/fuzztruction ./my-experiments/config/openvpn/openvpn.yml --log-output fuzz -j 1 -t 5m --purge --log-level trace 
```

## Other stuff
If server doesn't start for ip problems:
`sudo ip addr flush dev tun0`

Everything related to openvpn is in `my-experiments`.

## Problems faced
Dockerfile was broken.

`/dev/hwrng` was missing and the fuzzer couldn't start.

OpenVPN needs to run in user mode, which requires a pre-created tun0 device and sudo wrapper script for running ip commands. OpenVPN binaries need net capabilities inside Rust "jail".

This is all taken care of in `init.sh`.