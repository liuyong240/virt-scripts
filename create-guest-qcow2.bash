#!/bin/bash
#
# Copyright (C) 2014 Red Hat Inc.
# Author: <kashyap@redhat.com>
# Further contributions: <pjp@fedoraproject.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

# Script to create/install unattended Virtual Machines (with bridging)
#
# 1 Note: Bridging should be configured on the host to allow guests to be
#   in the same subnet as hosts
# 2 Creting a bridge, refer this: http://wiki.libvirt.org/page/Networking
# 3 The kickstart file contains minimal fedora pkgs like core and text internet
# 4 Also adds a serial console
#

#set -x

VERSION="0.1"
prog=`basename $0`

fstype="ext4"
IMAGE_HOME="/var/lib/libvirt/images"

burl="http://dl.fedoraproject.org/pub"
location1="$burl/fedora/linux/releases/19/Fedora/ARCH/os"
location2="$burl/fedora/linux/releases/20/Fedora/ARCH/os"


# Create a minimal kickstart file and return the temporary file name.
# Do remember to delete this temporary file when it is no longer required.
#
create_ks_file()
{
    dist=$1
    fkstart=$(mktemp -u --tmpdir=$(pwd) .XXXXXXXXXXXXXX)

    cat << EOF > $fkstart
install
text
reboot
lang en_US.UTF-8
keyboard us
network --bootproto dhcp
rootpw testpwd
firewall --enabled --ssh
selinux --enforcing
timezone --utc America/New_York
bootloader --location=mbr --append="console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH"
zerombr
clearpart --all --initlabel
autopart --type=$fstype

%packages
@core
%end
EOF
    echo "$fkstart"
}

create_guest()
{
    name=$1
    arch=$2
    dist=$3
    locn=$4
    dimg=$5
    fkst=$(create_ks_file $dist)
    bnam=$(basename $fkst)

    echo "Creating domain $name..."
    echo "Disk image will be created at: $dimg"

    # Create the qcow2 disk image with preallocation and 'fallocate'
    # (which pre-allocates all the blocks to a file) it for maximum
    # performance.
    #
    # fallocate -l `ls -al $diskimage | awk '{print $5}'` $diskimage
    #
    echo "Creating qcow2 disk image..."
    qemu-img create -f qcow2 -o preallocation=metadata $dimg 10G
    echo `ls -lash $dimg`

    virt-install --connect=qemu:///system \
    --network=bridge:virbr0 \
    --initrd-inject=$bnam \
    --extra-args="ks=file:/$bnam console=tty0 console=ttyS0,115200" \
    --name=$name \
    --disk path=$dimg,format=qcow2,cache=none \
    --ram 2048 \
    --vcpus=2 \
    --check-cpu \
    --accelerate \
    --cpuset auto \
    --os-type linux \
    --os-variant $dist \
    --hvm \
    --location=$locn \
    --nographics \
    --console=pty

    rm $fkst
    return 0
}

usage ()
{
    echo -e "Usage: $prog [OPTIONS] <vm-name> <distro> <arch>\n"
    echo "  distro: f19 f20"
    echo "    arch: i386, x86_64"
}

printh ()
{
    format="%-15s %s\n"

    usage;
    printf "\n%s\n\n" "OPTIONS:"
    printf "$format" "  -f <FSTYPE>" "specify file system type, default: ext4"
    printf "$format" "  -h" "display this help"
    printf "$format" "  -v" "display version information"
    printf "\nReport bugs to Kashyap <kashyap@redhat.com>\n"
}

check_options ()
{
    while getopts ":+f:hv" arg "$@";
    do
        case $arg in
            :)
            printf "$prog: missing argument\n"
            exit 0
            ;;

            f)
            fstype=$OPTARG
            ;;

            h)
            printh
            exit 0
            ;;

            v)
            printf "%s version %s\n" $prog $VERSION
            exit 0
            ;;

            *)
            printf "%s: invalid option\n" $prog
            exit 255
        esac
    done

    return $(($OPTIND - 1));
}

# main
{
    check_options $@;
    shift $?;

    # check if min no. of arguments are 3
    #
    if [ "$#" != 3 ]; then
        printh;
        exit 255
    fi

    # check if Linux bridging is configured
    #
    show_bridge=`brctl show | awk 'NR==2 {print $1}'`
    if [ $? -ne 0 ] ; then
        echo "Bridged Networking is not configured. " \
             "please do so if your guest needs an IP similar to your host."
        exit 255
    fi

    name=$1
    dist=$2
    arch=$3
    dimg="$IMAGE_HOME/$name.qcow2"

    locn=""
    case "$dist" in
        f19)
        dist="fedora19"
        locn=${location1/ARCH/$arch}
        ;;

        f20)
        dist="fedora20"
        locn=${location2/ARCH/$arch}
        ;;


        *)
        echo "$0: invalid distribution name"
        exit 255
    esac
    create_guest $name $arch $dist $locn $dimg

    exit 0
}
