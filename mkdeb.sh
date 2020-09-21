#!/bin/bash


usage() 
{
	echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
	echo "+  usage : ./mkdeb.sh <kernel_dir> <arm-trusted-firmware_dir> [out_dir]                                    +"
	echo "+  kernel_dir : linux-4.9.y sources path                                                                   +"
	echo "+  arm-trusted-firmware_dir:  arm trusted firmware directory path                                          +"
	echo "+  out_dir:  output directory                                                                              +"
	echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
}


CUR_DIR=`pwd`
OUT_DIR="${CUR_DIR}/out"
KERNEL_DIR=""
ARM_TRUSTED_FIRMWARE_DIR=""
SUFFIX=`date +"%Y%m%d%H%M"`

log() {
	cur_date=`date +"%Y-%m-%d %H:%M:%S"`
        echo "$cur_date "$1
}

param_check() {
	if [ $# -eq 2 ]; then
        KERNEL_DIR="$1"
        ARM_TRUSTED_FIRMWARE_DIR="$2"
	elif [ $# -eq 3 ]; then
        KERNEL_DIR="$1"
        ARM_TRUSTED_FIRMWARE_DIR="$2"
        OUT_DIR="$3"
	else
		usage
		return 1
	fi

    if [ ! -d ${KERNEL_DIR} ] || [ ! -d ${ARM_TRUSTED_FIRMWARE_DIR} ]; then
        usage
        echo "${KERNEL_DIR} or ${ARM_TRUSTED_FIRMWARE_DIR} is not exist!!"
        return 1
    fi

    rm -rf ${OUT_DIR}
    mkdir -v ${OUT_DIR}

	return 0
}

install_debian_files() {
    debian_dir=${CUR_DIR}/DEBIAN
    if [ ! -d ${debian_dir} ]; then
        echo "Can't find DEBIAN files, please check current path!"
        return 1
    fi 
    cp -a ${debian_dir} ${OUT_DIR}/
    log "copy DEBIAN finished"

    return 0
}

install_kernel_image() {

    if [ ! -e ${ARM_TRUSTED_FIRMWARE_DIR}/build/hi3559av100/debug/fip.bin ]; then
        log "Can't fine fip.bin, please compile first!!"
        return 1
    fi
    mkdir -pv ${OUT_DIR}/boot
    cp ${ARM_TRUSTED_FIRMWARE_DIR}/build/hi3559av100/debug/fip.bin ${OUT_DIR}/boot/fip-${SUFFIX}.bin
    ln -sf fip-${SUFFIX}.bin ${OUT_DIR}/boot/fip.bin

    log "copy kernel image fip.bin finished"

    return 0
}

install_kernel_modules() {

    if [ ! -n "$(find ${KERNEL_DIR} -name *.ko)" ]; then
        log "Can't fine kernel modules, please make modules first!!"
        return 1
    fi

    pushd ${KERNEL_DIR}
    make ARCH=arm64 CROSS_COMPILE=aarch64-himix100-linux- INSTALL_MOD_PATH=${OUT_DIR} -j8 modules_install
    popd

    log "install kernel modules finished"

    return 0
}

param_check $*
if [ x"1" == x"$?" ]; then
    exit 1;
fi

install_debian_files
if [ x"1" == x"$?" ]; then
    exit 1;
fi

install_kernel_image
if [ x"1" == x"$?" ]; then
    exit 1;
fi

install_kernel_modules
if [ x"1" == x"$?" ]; then
    exit 1;
fi

dpkg-deb -b ${OUT_DIR} kernel-haibo-${SUFFIX}.deb

exit 0
