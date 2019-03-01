#!/bin/bash
################################################################################
#
# Build HPC Image with Environment Modules 
#
# OpenMPI, IntelMPI 2018.4, MPICH, MVAPICH
#
# Tested On: CentOS 7.6
#
################################################################################
set -xeo pipefail #-- strict/exit on fail
exec 2>&1 # funnel stderr back to packer client console

if [[ $(id -u) -ne 0 ]] ; then
        echo "Must be run as root"
        exit 1
fi

NUM_CPUS=$( cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l )
INSTALL_PREFIX=/opt

# temporarily stop yum service conflicts if applicable
set +e
systemctl stop yum.cron
systemctl stop packagekit
set -e

# wait for wala to finish downloading driver updates
sleep 60

# temporarily stop waagent
systemctl stop waagent.service

# cleanup any aborted yum transactions
yum-complete-transaction --cleanup-only

install_essentials() 
{
    # install essential packages
    yum install -y epel-release
    yum install -y nfs-utils jq htop axel git pdsh nmap
    yum install -y numactl numactl-devel
    yum install -y redhat-rpm-config rpm-build gcc-gfortran gcc-c++ byacc
    yum install -y gtk2 atk cairo tcl tk createrepo
    yum install -y xml2 libxml2 libxml2-devel zlib gmp mpfr
    yum install -y python-setuptools

} #-- install_essentials() --#

configure_system()
{
     # set limits for HPC apps
     cat << EOF >> /etc/security/limits.conf
*               hard    memlock         unlimited
*               soft    memlock         unlimited
*               hard    nofile          65535
*               soft    nofile          65535
EOF

    # turn off GSS proxy
    sed -i 's/GSS_USE_PROXY="yes"/GSS_USE_PROXY="no"/g' /etc/sysconfig/nfs

    # Disable tty requirement for sudo
    sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

    setenforce 0
    # Disable SELinux
cat << EOF > /etc/selinux/config
# This file controls the state of SELinux on the system.
# SELINUX= can take one of these three values:
#       enforcing - SELinux security policy is enforced.
#       permissive - SELinux prints warnings instead of enforcing.
#       disabled - No SELinux policy is loaded.
SELINUX=disabled
# SELINUXTYPE= can take one of these two values:
#       targeted - Targeted processes are protected,
#       mls - Multi Level Security protection.
SELINUXTYPE=targeted
EOF

    # optimize
    systemctl disable cpupower
    systemctl disable firewalld

} #-- end of configure_system() --#

install_beegfs_client()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "*           Installing BeeGFS Client                    *" 
    echo "*                                                       *"
    echo "*********************************************************"
	wget -O /etc/yum.repos.d/beegfs-rhel7.repo https://www.beegfs.io/release/beegfs_7/dists/beegfs-rhel7.repo
	rpm --import https://www.beegfs.io/release/latest-stable/gpg/RPM-GPG-KEY-beegfs

	yum install -y beegfs-client beegfs-helperd beegfs-utils gcc gcc-c++
    set +e
	yum install -y "kernel-devel-uname-r == $(uname -r)"
    set -e

	sed -i 's/^sysMgmtdHost.*/sysMgmtdHost = localhost/g' /etc/beegfs/beegfs-client.conf
	echo "/beegfs /etc/beegfs/beegfs-client.conf" > /etc/beegfs/beegfs-mounts.conf
	
	systemctl daemon-reload
	systemctl enable beegfs-helperd.service
	systemctl enable beegfs-client.service

} #-- end of install_beegfs_client() --#

install_intel_mpi_2018()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "*           Installing Intel MPI & Tools                *" 
    echo "*                                                       *"
    echo "*********************************************************"
    IMPI_VERSION=2018.4-057  
    IMPI_BUILD=2018.4.274
    MKL_VERSION=2018.4-057
    yum -y install yum-utils
    yum-config-manager --add-repo https://yum.repos.intel.com/setup/intelproducts.repo
    rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
    yum -y install intel-mkl-${MKL_VERSION} intel-mpi-${IMPI_VERSION}
    #source /opt/intel/mkl/bin/mklvars.sh intel64
    #source /opt/intel/impi/${IMPI_BUILD}/intel64/bin/mpivars.sh

} #-- end of install_intel_mpi_2018() --#

install_ucx()
{
    echo "********************************* ************************"
    echo "*                                                       *"
    echo "*                 Installing UCX                        *" 
    echo "*                                                       *"
    echo "*********************************************************"
    # UCX 1.5.0 RC1
    wget https://github.com/openucx/ucx/releases/download/v1.5.0-rc1/ucx-1.5.0.tar.gz
    tar -xvf ucx-1.5.0.tar.gz
    cd ucx-1.5.0
    ./contrib/configure-release --prefix=${INSTALL_PREFIX}/ucx-1.5.0 && make -j"${NUM_CPUS}" && make install
    cd ..

} #-- end of install_ucx() --#

install_hpcx()
{
    echo "********************************* ************************"
    echo "*                                                       *"
    echo "*                 Installing HPC-X                      *" 
    echo "*                                                       *"
    echo "*********************************************************"
    # HPC-X v2.3.0
    pushd ${INSTALL_PREFIX}
    wget http://www.mellanox.com/downloads/hpc/hpc-x/v2.3/hpcx-v2.3.0-gcc-MLNX_OFED_LINUX-4.5-1.0.1.0-redhat7.6-x86_64.tbz
    tar -xvf hpcx-v2.3.0-gcc-MLNX_OFED_LINUX-4.5-1.0.1.0-redhat7.6-x86_64.tbz
    HPCX_PATH=${INSTALL_PREFIX}/hpcx-v2.3.0-gcc-MLNX_OFED_LINUX-4.5-1.0.1.0-redhat7.6-x86_64
    HCOLL_PATH=${HPCX_PATH}/hcoll
    rm -rf hpcx-v2.3.0-gcc-MLNX_OFED_LINUX-4.5-1.0.1.0-redhat7.6-x86_64.tbz
    popd
 
} #-- end of install_hpcx() --#

install_openmpi()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "*             Installing OpenMPI 4.0.0                  *" 
    echo "*                                                       *"
    echo "*********************************************************"
    # OpenMPI 4.0.0
    wget https://download.open-mpi.org/release/open-mpi/v4.0/openmpi-4.0.0.tar.gz
    tar -xvf openmpi-4.0.0.tar.gz
    cd openmpi-4.0.0
    ./configure --prefix=${INSTALL_PREFIX}/openmpi-4.0.0 --with-ucx=${INSTALL_PREFIX}/ucx-1.5.0 --enable-mpirun-prefix-by-default && make -j"${NUM_CPUS}" && make install
    cd ..

} #-- end of install_openmpi() --#

install_mvapich()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "*               Installing MVAPICH 2.3                  *" 
    echo "*                                                       *"
    echo "*********************************************************"
    wget http://mvapich.cse.ohio-state.edu/download/mvapich/mv2/mvapich2-2.3.tar.gz
    tar -xvf mvapich2-2.3.tar.gz
    cd mvapich2-2.3
    ./configure --prefix=${INSTALL_PREFIX}/mvapich2-2.3 --enable-g=none --enable-fast=yes && make -j"${NUM_CPUS}" && make install
    cd ..

} #-- end of mvapich() --#

install_mpich()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "*                Installing MPICH 3.3                   *" 
    echo "*                                                       *"
    echo "*********************************************************"
    wget http://www.mpich.org/static/downloads/3.3/mpich-3.3.tar.gz
    tar -xvf mpich-3.3.tar.gz
    cd mpich-3.3
    ./configure --prefix=${INSTALL_PREFIX}/mpich-3.3 --with-ucx=${INSTALL_PREFIX}/ucx-1.5.0 --with-hcoll=${HCOLL_PATH} --enable-g=none --enable-fast=yes --with-device=ch4:ucx   && make -j"${NUM_CPUS}" && make install 
    cd ..

} #-- end of mpich() --#

install_mlx_ofed_centos76()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "*           Installing Mellanox OFED drivers            *" 
    echo "*                                                       *"
    echo "*********************************************************"
    KERNEL=$(uname -r)
    yum install -y kernel-devel-${KERNEL} python-devel
    
    wget --retry-connrefused \
        --tries=3 \
        --waitretry=5 \
        http://content.mellanox.com/ofed/MLNX_OFED-4.5-1.0.1.0/MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64.tgz
        
    tar zxvf MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64.tgz
    
    ./MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-x86_64/mlnxofedinstall \
        --add-kernel-support \
        --skip-repo

} #-- install_mlx_ofed_centos76() --#

install_lis()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "* Installing Microsoft Linux Integration Services (LIS) *"
    echo "*                                                       *"
    echo "*********************************************************"
    pushd /mnt/resource
    set +e
    wget --retry-connrefused --read-timeout=10 https://aka.ms/lis
    tar xvzf lis
    cd LISISO
    #./upgrade.sh # BUG
    ./install.sh
    popd
    set -e

} #-- end of install_lis() --#

install_gcc731()
{
    echo "*********************************************************"
    echo "*                                                       *"
    echo "*               Installing GCC 7.3.1                    *" 
    echo "*                                                       *"
    echo "*********************************************************"
    yum install centos-release-scl-rh -y
    yum --enablerepo=centos-sclo-rh-testing install devtoolset-7-gcc -y
    yum --enablerepo=centos-sclo-rh-testing install devtoolset-7-gcc-c++ -y
    yum --enablerepo=centos-sclo-rh-testing install devtoolset-7-gcc-gfortran -y

} #-- install_gcc731() --#

install_modules()
{
    yum install -y environment-modules
    git clone https://github.com/mkiernan/azhpcmodules.git
    cd azhpcmodules
    cp -R ./mpi /usr/share/Modules/modulefiles/
    cp ./compiler/gcc-7.3.1 /usr/share/Modules/modulefiles/
    pushd /usr/share/Modules/modulefiles/
    rm -rf module-info module-git dot null use.own modules
    popd

} #-- end of install_modules() --#

install_WALA()
{
    # Install WALinuxAgent
    mkdir -p /tmp/wala
    cd /tmp/wala
    wget https://github.com/Azure/WALinuxAgent/archive/v2.2.36.tar.gz
    tar -xvf v2.2.36.tar.gz
    cd WALinuxAgent-2.2.36
    python setup.py install --register-service --force
    sed -i -e 's/# OS.EnableRDMA=y/OS.EnableRDMA=y/g' /etc/waagent.conf
    sed -i -e 's/AutoUpdate.Enabled=y/# AutoUpdate.Enabled=y/g' /etc/waagent.conf
    systemctl restart waagent
    cd && rm -rf /tmp/wala

} #-- end of install_WALA() --#

#yum update -y WALinuxAgent

install_essentials
configure_system

# check if running on HB/HC
VMSIZE=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-12-01" | jq -r '.compute.vmSize')
VMSIZE=${VMSIZE,,}
echo "vmSize is $VMSIZE"
if [ "$VMSIZE" == "standard_hb60rs" ] || [ "$VMSIZE" == "standard_hc44rs" ]
then
    set +e
    install_mlx_ofed_centos76
    install_lis
    echo 1 >/proc/sys/vm/zone_reclaim_mode
    echo "vm.zone_reclaim_mode = 1" >> /etc/sysctl.conf
    sysctl -p
    set -e
fi
install_WALA
install_intel_mpi_2018
install_ucx
install_hpcx
install_openmpi
install_mpich
install_mvapich
install_gcc731
install_modules

ifconfig

echo "End of base image "
