#!/bin/bash

set -x
#set -xeuo pipefail #-- strict/exit on fail

if [[ $(id -u) -ne 0 ]] ; then
	echo "Must be run as root"
	exit 1
fi

yum -y install yum-utils
yum-config-manager --add-repo https://yum.repos.intel.com/setup/intelproducts.repo
rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
yum -y update
yum -y install intel-mkl intel-mpi
yum -y install wget make which gcc gcc-gfortran tar gzip
wget https://gitlab.com/QEF/q-e/-/archive/qe-6.3/q-e-qe-6.3.tar.gz
tar -xvzf q-e-qe-6.3.tar.gz
rm q-e-qe-6.3.tar.gz
cd q-e-qe-6.3/
export MANPATH=/opt/intel/impi/2018.4.274/linux/mpi/man
source /opt/intel/mkl/bin/mklvars.sh intel64
source /opt/intel/impi/2018.4.274/intel64/bin/mpivars.sh
./configure
make all
