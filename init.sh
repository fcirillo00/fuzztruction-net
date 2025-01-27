#!/bin/bash

# initialize /dev/hwrng device for jail init (fails otherwise)
sudo mknod /dev/hwrng c 1 8

# fuzzer says to run these commands at first
echo core | sudo tee /proc/sys/kernel/core_pattern
echo 1 | sudo tee /proc/sys/kernel/perf_event_paranoid

# initialize dev tun0 tun1 for openvpn no root mode
sudo my-experiments/build/openvpn/generator/openvpn --rmtun --dev tun0
sudo my-experiments/build/openvpn/generator/openvpn --mktun --dev tun0 --dev-type tun --user user --group user

sudo my-experiments/build/openvpn/generator/openvpn --rmtun --dev tun1
sudo my-experiments/build/openvpn/generator/openvpn --mktun --dev tun1 --dev-type tun --user user --group user

# create sudo wrapper for ip commands
sudo sh -c 'echo "#!/bin/sh\nsudo /sbin/ip \$*" > /usr/local/sbin/unpriv-ip'
sudo chmod 755 /usr/local/sbin/unpriv-ip

# grant sudo access to unpriv-ip for user
sudo sh -c 'echo "user ALL=(ALL) NOPASSWD: /sbin/ip" >> /etc/sudoers'