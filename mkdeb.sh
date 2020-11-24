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
#SUFFIX=`date +"%Y%m%d%H%M"`
TAG=1.0
KERNELRELEASE="4.9.37-${TAG}"

tmpdir="${OUT_DIR}/tmp"
kernel_headers_dir="${OUT_DIR}/hdrtmp"
libc_headers_dir="${OUT_DIR}/headertmp"
debian_dir="${OUT_DIR}/debian"


version=4.9.37
distribution="haibo"
revision=""
packagename=linux-image-haibo
kernel_headers_packagename=linux-headers-haibo
libc_headers_packagename=linux-libc-dev-haibo

maintainer="qiaoshouxing <qiaoshouxingsdd@163.com>"
sourcename=linux
packageversion=${KERNELRELEASE}
debarch=arm64
forcearch="-DArchitecture=${debarch}"

log() {
	cur_date=`date +"%Y-%m-%d %H:%M:%S"`
    echo "$cur_date "$1
}

create_package() {
	local pname="$1" pdir="$2"

	mkdir -m 755 -p "$pdir/DEBIAN"
	mkdir -p "$pdir/usr/share/doc/$pname"
	cp ${debian_dir}/copyright "$pdir/usr/share/doc/$pname/"
	cp ${debian_dir}/changelog "$pdir/usr/share/doc/$pname/changelog.Debian"
	gzip -9 "$pdir/usr/share/doc/$pname/changelog.Debian"
	sh -c "cd '$pdir'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
		| xargs -r0 md5sum > DEBIAN/md5sums"

	# Fix ownership and permissions
	chown -R root:root "$pdir"
	chmod -R go-w "$pdir"
	# in case we are in a restrictive umask environment like 0077
	chmod -R a+rX "$pdir"

	# Create the package
	dpkg-gencontrol $forcearch -Vkernel:debarch="${debarch}" -p$pname -P"$pdir"
	dpkg --build "$pdir" ..
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

	return 0
}

prepare_debian_files() {
    rm -rf ${OUT_DIR}
    mkdir -pv ${kernel_headers_dir}
    mkdir -pv ${libc_headers_dir}
    mkdir -pv ${debian_dir}

    # Generate a simple changelog template
    cat <<EOF > ${debian_dir}/changelog
$sourcename ($packageversion) $distribution; urgency=low

  * Custom built haibo Linux kernel.

 -- $maintainer  $(date -R)
EOF

    # Generate copyright file
    cat <<EOF > ${debian_dir}/copyright
This is a packacked upstream version of the Linux kernel.

The sources may be found at most Linux ftp sites, including:
ftp://ftp.kernel.org/pub/linux/kernel

Copyright: 1991 - 2015 Linus Torvalds and others.

The git repository for mainline kernel development is at:
git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; version 2 dated June, 1991.

On Debian GNU/Linux systems, the complete text of the GNU General Public
License version 2 can be found in \`/usr/share/common-licenses/GPL-2'.
EOF


    # Generate a control file
    cat <<EOF > ${debian_dir}/control
Source: $sourcename
Section: kernel
Priority: optional
Maintainer: $maintainer
Build-Depends: bc, kmod, cpio
Standards-Version: 4.9.37
Homepage: http://www.kernel.org/
EOF

	cat <<EOF >> ${debian_dir}/control

Package: $packagename
Provides: linux-image, linux-image-2.6, linux-modules-${KERNELRELEASE}
Architecture: any
Description: Linux kernel, version ${KERNELRELEASE}
 This package contains the Linux kernel, modules and corresponding other
 files, version: ${KERNELRELEASE}.
EOF


    cat <<EOF >> ${debian_dir}/control

Package: $kernel_headers_packagename
Provides: linux-headers, linux-headers-2.6
Architecture: any
Description: Linux kernel headers for $KERNELRELEASE on \${kernel:debarch}
 This package provides kernel header files for $KERNELRELEASE on \${kernel:debarch}
 .
 This is useful for people who need to build external modules
EOF

    cat <<EOF >> ${debian_dir}/control

Package: $libc_headers_packagename
Section: devel
Provides: linux-kernel-headers
Architecture: any
Description: Linux support headers for userspace development
 This package provides userspaces headers from the Linux kernel.  These headers
 are used by the installed headers for GNU glibc and other system libraries.
EOF


    log "prepare DEBIAN finished"

    return 0
}

install_kernel_image() {

    if [ ! -e ${ARM_TRUSTED_FIRMWARE_DIR}/build/hi3559av100/debug/fip.bin ]; then
        log "Can't fine fip.bin, please compile first!!"
        return 1
    fi
    mkdir -pv ${tmpdir}/boot
    cp ${ARM_TRUSTED_FIRMWARE_DIR}/build/hi3559av100/debug/fip.bin ${tmpdir}/boot/fip-${KERNELRELEASE}.bin
    ln -sf fip-${KERNELRELEASE}.bin ${tmpdir}/boot/fip.bin

    log "copy kernel image fip.bin finished"

	cp ${KERNEL_DIR}/System.map "${tmpdir}/boot/System.map-${KERNELRELEASE}"
	cp ${KERNEL_DIR}/.config "${tmpdir}/boot/config-${KERNELRELEASE}"

    log "copy kernel configure and map file finished"

    return 0
}

install_kernel_modules() {

    if [ ! -n "$(find ${KERNEL_DIR} -name *.ko)" ]; then
        log "Can't fine kernel modules, please make modules first!!"
        return 1
    fi

    pushd ${KERNEL_DIR}
    make ARCH=arm64 CROSS_COMPILE=aarch64-himix100-linux- INSTALL_MOD_PATH=${tmpdir} -j8 modules_install
    popd

	rm -f "${tmpdir}/lib/modules/${version}/build"
	rm -f "${tmpdir}/lib/modules/${version}/source"

    log "install kernel modules finished"

    return 0
}

install_kernel_headers() {
    # 将用户态程序所需的内核头文件进行搜集，放置到目标文件夹中
    pushd ${KERNEL_DIR}
	make ARCH=arm64 CROSS_COMPILE=aarch64-himix100-linux- headers_check
	make ARCH=arm64 CROSS_COMPILE=aarch64-himix100-linux- INSTALL_HDR_PATH="$libc_headers_dir/usr"  headers_install

    # 从内核源码目录搜集编译模块用的文件：头文件、makefile文件、工具、链接文件、Kconfig文件、符号表等
    find . -name Makefile\* -o -name Kconfig\* -o -name \*.pl > "${debian_dir}/hdrsrcfiles"
    find arch/*/include include scripts -type f >> "${debian_dir}/hdrsrcfiles"
    find arch/arm64 -name module.lds -o -name Kbuild.platforms -o -name Platform >> "${debian_dir}/hdrsrcfiles"
    find $(find arch/arm64 -name include -o -name scripts -type d) -type f >> "${debian_dir}/hdrsrcfiles"
    find tools/include -type f >> "${debian_dir}/hdrsrcfiles"
    if grep -q '^CONFIG_STACK_VALIDATION=y' .config ; then
        find tools/objtool -type f -executable >> "${debian_dir}/hdrobjfiles"
    fi
    find arch/arm64/include Module.symvers include scripts -type f >> "${debian_dir}/hdrobjfiles"
    if grep -q '^CONFIG_GCC_PLUGINS=y' .config ; then
        find scripts/gcc-plugins -name \*.so -o -name gcc-common.h >> "${debian_dir}/hdrobjfiles"
    fi
    popd

    # 搜集的文件进行打包集中放到目标文件夹中
    destdir=$kernel_headers_dir/usr/src/linux-headers-${KERNELRELEASE}
    mkdir -p "$destdir"
    (cd ${KERNEL_DIR}; tar -c -f - -T -) < "${debian_dir}/hdrsrcfiles" | (cd $destdir; tar -xf -)
    (cd ${KERNEL_DIR}; tar -c -f - -T -) < "${debian_dir}/hdrobjfiles" | (cd $destdir; tar -xf -)
    (cp ${KERNEL_DIR}/.config $destdir/.config) # copy .config manually to be where it's expected to be
    mkdir -p "$kernel_headers_dir/lib/modules/$version/"
    ln -sf "/usr/src/linux-headers-${KERNELRELEASE}" "$kernel_headers_dir/lib/modules/$version/build"
    rm -f "${debian_dir}/hdrsrcfiles" "${debian_dir}/hdrobjfiles"


    log "install kernel header files finished"

    return 0
}

param_check $*
if [ x"1" == x"$?" ]; then
    exit 1;
fi


# 预先准备debian control文件及相应文件夹
prepare_debian_files

# 准备内核文件
install_kernel_image
if [ x"1" == x"$?" ]; then
    exit 1;
fi

# 准备驱动模块文件
install_kernel_modules
if [ x"1" == x"$?" ]; then
    exit 1;
fi

# 准备内核头文件(分为两部分：用户态程序需要、内核模块编译需要)
install_kernel_headers


# 编译debian软件包
pushd ${OUT_DIR}
create_package "$packagename" "$tmpdir"
create_package "$kernel_headers_packagename" "$kernel_headers_dir"
create_package "$libc_headers_packagename" "$libc_headers_dir"
popd

log "success!!!!!"

exit 0
