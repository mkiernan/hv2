#!/bin/bash

# fail on any error
set -e

HEADNODE=10.0.2.4

sed -i 's/^ResourceDisk.MountPoint=\/mnt\/resource$/ResourceDisk.MountPoint=\/mnt\/local_resource/g' /etc/waagent.conf
umount /mnt/resource

mkdir -p /mnt/resource/scratch

cat << EOF >> /etc/fstab
$HEADNODE:/home    /home   nfs defaults 0 0
$HEADNODE:/mnt/resource/scratch    /mnt/resource/scratch   nfs defaults 0 0
EOF
mount -a

# Don't require password for HPC user sudo
echo "hpcuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
# Disable tty requirement for sudo
sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

# https://software.intel.com/en-us/articles/installing-intel-free-libs-and-python-yum-repo
#
yum-config-manager --add-repo https://yum.repos.intel.com/setup/intelproducts.repo
rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
yum -y update
#yum -y install intel-mkl intel-mpi
#yum -y install intel-mkl-2018.4-274
yum -y install intel-mkl-2018.4-057
yum -y install intel-mpi-2018.4-057
