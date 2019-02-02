#!/bin/bash

set -x
#set -xeuo pipefail #-- strict/exit on fail

if [[ $(id -u) -ne 0 ]] ; then
	echo "Must be run as root"
	exit 1
fi

yum update -y
yum --enablerepo=extras install -y -q epel-release
yum install -y nfs-utils htop pdsh psmisc

# update LIS
wget https://aka.ms/lis
tar xzf lis
pushd LISISO
./upgrade.sh
yum update -y WALinuxAgent
popd
rm -rf lis; rm -rf LISISO

#install mellanox driver
yum install -y kernel-devel python-devel
yum install -y kernel-devel-3.10.0-957.1.3.el7.x86_64
yum install -y redhat-rpm-config rpm-build gcc-gfortran gcc-c++
yum install -y gtk2 atk cairo tcl tk createrepo
wget http://content.mellanox.com/ofed/MLNX_OFED-4.5-1.0.1.0/MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64.tgz
tar zxvf MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64.tgz
./MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64/mlnxofedinstall --add-kernel-support
/etc/init.d/openibd restart
rm -rf ./MLNX_*

# Use WALinuxAgent to assign IP address and make it persist
yum install -y python-setuptools
yum install -y git
git clone https://github.com/Azure/WALinuxAgent.git
pushd WALinuxAgent
wget https://patch-diff.githubusercontent.com/raw/Azure/WALinuxAgent/pull/1365.patch
wget https://patch-diff.githubusercontent.com/raw/Azure/WALinuxAgent/pull/1375.patch
wget https://patch-diff.githubusercontent.com/raw/Azure/WALinuxAgent/pull/1389.patch
git reset --hard 72b643ea93e5258c3cec0e778017936806111f15
git am 1*.patch
python setup.py install --register-service
sed -i -e 's/# OS.EnableRDMA=y/OS.EnableRDMA=y/g' /etc/waagent.conf
sed -i -e 's/AutoUpdate.Enabled=y/# AutoUpdate.Enabled=y/g' /etc/waagent.conf
systemctl restart waagent
popd
rm -rf WALinuxAgent

#automatically reclaim memory to avoid remote memory access 
echo 1 >/proc/sys/vm/zone_reclaim_mode
echo "vm.zone_reclaim_mode = 1" >> /etc/sysctl.conf sysctl -p

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
