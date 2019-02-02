#!/bin/bash

set -x
#set -xeuo pipefail #-- strict/exit on fail

if [[ $(id -u) -ne 0 ]] ; then
	echo "Must be run as root"
	exit 1
fi

USER=hpcuser

IP=`ifconfig eth0 | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
localip=`echo $IP | cut --delimiter='.' -f -3`

mkdir -p /mnt/resource/scratch
chmod a+rwx /mnt/resource/scratch

cat << EOF >> /etc/exports
/home 10.0.2.0/23(rw,sync,no_root_squash,no_all_squash)
/mnt/resource/scratch 10.0.2.0/23(rw,sync,no_root_squash,no_all_squash)
EOF

systemctl enable rpcbind
systemctl enable nfs-server
systemctl enable nfs-lock
systemctl enable nfs-idmap
systemctl start rpcbind
systemctl start nfs-server
systemctl start nfs-lock
systemctl start nfs-idmap
systemctl restart nfs-server

mkdir -p /home/$USER/bin
chown $USER:$USER /home/$USER/bin

cat << EOF >> /home/$USER/.bashrc
export WCOLL=/home/$USER/bin/hostlist
EOF
chown $USER:$USER /home/$USER/.bashrc

touch /home/hpcuser/bin/hostlist
chown hpcuser:hpcuser /home/hpcuser/bin/hostlist

ssh-keygen -f /home/$USER/.ssh/id_rsa -t rsa -N ''
cat << EOF > /home/$USER/.ssh/config
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    PasswordAuthentication no
    LogLevel QUIET
EOF
cat /home/$USER/.ssh/id_rsa.pub >> /home/$USER/.ssh/authorized_keys
chmod 644 /home/$USER/.ssh/config
chown $USER:$USER /home/$USER/.ssh/*

# Don't require password for HPC user sudo
echo "$USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
# Disable tty requirement for sudo
sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

#
# add .screenrc file
#
cat << EOF > /home/$USER/.screenrc
screen -t "top"  0 top
screen -t "bash 1"  0 bash

defscrollback 10000

sessionname local
shelltitle bash
startup_message off

vbell off

bind = resize =
bind + resize +2
bind - resize -2
bind _ resize max

caption always "%{= wr} $HOSTNAME %{= wk} %-Lw%{= wr}%n%f %t%{= wk}%+Lw %{= wr} %=%c %Y-%m-%d "

zombie cr
escape ^]]
EOF
chown $USER:$USER /home/$USER/.screenrc

cd /home/$USER
git clone -b https://github.com/mkiernan/hv2.git
mv hv2 azhpc
chown $USER:$USER -R azhpc
chmod +x azhpc/scripts/*
cd /home/$USER/bin
for i in /home/$USER/azhpc/scripts/*; do
	ln -s $i
done

rm -f install.py
