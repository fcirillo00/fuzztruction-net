#!/bin/bash

# initialize /dev/hwrng device for jail init (fails otherwise)
sudo mknod /dev/hwrng c 1 8

# initialize dev tun0 for openvpn no root mode
sudo my-experiments/build/openvpn/generator/openvpn --rmtun --dev tun0
sudo my-experiments/build/openvpn/generator/openvpn --mktun --dev tun0 --dev-type tun --user user --group user

# create sudo wrapper for ip commands
sudo sh -c 'echo "#!/bin/sh\nsudo /sbin/ip \$*" > /usr/local/sbin/unpriv-ip'
sudo chmod 755 /usr/local/sbin/unpriv-ip

# grant sudo access to unpriv-ip for user
sudo sh -c 'echo "user ALL=(ALL) NOPASSWD: /sbin/ip" >> /etc/sudoers'