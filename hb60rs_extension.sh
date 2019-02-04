#!/bin/bash

# This script is intended not as a dynamic extension, but just to apply to
# an HB60rs machine to create a static image. NB: It takes ~20 mins to run. 
# Includes the mellanox driver, intelmpi and all current advised best practises.
# Suggest to run manualy on a console rather than as an extension - seems to 
# hang when running as an extension due to the waagent reconfiguration. 
# To run: 
# wget https://raw.githubusercontent.com/mkiernan/hv2/master/hb60rs_extension.sh 
# sudo ./hb60rs_extension.sh

set -x
#set -xeuo pipefail #-- strict/exit on fail

if [[ $(id -u) -ne 0 ]] ; then
	echo "Must be run as root"
	exit 1
fi

yum update -y
yum --enablerepo=extras install -y -q epel-release
yum install -y nfs-utils htop pdsh psmisc axel screen nmap

# update LIS
wget https://aka.ms/lis
tar xzf lis
pushd LISISO
./upgrade.sh
popd
rm -rf lis; rm -rf LISISO

#install mellanox driver
yum install -y numactl
yum install -y kernel-devel python-devel redhat-rpm-config rpm-build gcc-gfortran gcc-c++ gtk2 atk cairo tcl tk createrepo
#yum install -y kernel-devel-3.10.0-957.1.3.el7.x86_64
wget http://content.mellanox.com/ofed/MLNX_OFED-4.5-1.0.1.0/MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64.tgz
tar zxvf MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64.tgz
./MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64/mlnxofedinstall --add-kernel-support
sed -i 's/LOAD_EIPOIB=no/LOAD_EIPOIB=yes/g' /etc/infiniband/openib.conf
/etc/init.d/openibd restart
rm -rf ./MLNX_*

systemctl stop waagent.service
yum update -y WALinuxAgent

# install intel mpi 2018.4 - find this a bit too slow for an extension also, so bake it into the image.
# https://software.intel.com/en-us/articles/installing-intel-free-libs-and-python-yum-repo
#
yum-config-manager --add-repo https://yum.repos.intel.com/setup/intelproducts.repo
rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
yum -y update
#yum -y install intel-mkl intel-mpi
#yum -y install intel-mkl-2018.4-274
yum -y install intel-mkl-2018.4-057
yum -y install intel-mpi-2018.4-057

#automatically reclaim memory to avoid remote memory access 
echo "vm.zone_reclaim_mode = 1" >> /etc/sysctl.conf

#disable firewall & SELinux 
systemctl stop iptables.service
systemctl disable iptables.service
systemctl mask firewalld
systemctl stop firewalld.service
systemctl disable firewalld.service
iptables -nL
sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

#disable cpu power
/bin/systemctl stop cpupower.service

#setup user limits for MPI
cat << EOF >> /etc/security/limits.conf
*               hard    memlock         unlimited
*               soft    memlock         unlimited
*               hard    nofile          65535
*               soft    nofile          65535
EOF
