#!/bin/bash

echo "========================= begin $0 ==========================="
source make.env
source public_funcs
init_work_env

# 盒子型号识别参数 
PLATFORM=amlogic
SOC=s912
BOARD=zyxq

SUBVER=$1

# Kernel image sources
###################################################################
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
check_file ${MODULES_TGZ}
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
check_file ${BOOT_TGZ}
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-amlogic-${KERNEL_VERSION}.tar.gz
check_file ${DTBS_TGZ}
K510=$(get_k510_from_boot_tgz "${BOOT_TGZ}" "vmlinuz-${KERNEL_VERSION}")
export K510
###########################################################################

# Openwrt root 源文件
OP_ROOT_TGZ="openwrt-armvirt-64-default-rootfs.tar.gz"
OPWRT_ROOTFS_GZ="${PWD}/${OP_ROOT_TGZ}"
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# 目标镜像文件
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 补丁和脚本
###########################################################################
BANNER="${PWD}/files/banner"

FMW_HOME="${PWD}/files/firmware"

UBOOT_WITHOUT_FIP_HOME="${PWD}/files/meson_btld/without_fip"
UBOOT_WITHOUT_FIP="u-boot-zyxq.bin"

FIRMWARE_TXZ="${PWD}/files/firmware_armbian.tar.xz"
BOOTFILES_HOME="${PWD}/files/bootfiles/amlogic"

FIRSTRUN_SCRIPT="${PWD}/files/first_run.sh"
###########################################################################

check_depends

SKIP_MB=4
BOOT_MB=160
ROOTFS_MB=736
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB))
create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "msdos" "$SKIP_MB" "$BOOT_MB" "fat32" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "fat32" "BOOT" "R" "btrfs" "ROOTFS"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "vfat"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"
echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc
extract_rootfs_files
extract_amlogic_boot_files

echo "修改引导分区相关配置 ... "
cd $TGT_BOOT
rm -f uEnv.ini
cat > uEnv.txt <<EOF
LINUX=/zImage
INITRD=/uInitrd

FDT=/dtb/amlogic/meson-gxm-octopus-planet.dtb

APPEND=root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF

echo "uEnv.txt -->"
echo "==============================================================================="
cat uEnv.txt
echo "==============================================================================="
echo

echo "修改根文件系统相关配置 ... "
cd $TGT_ROOT
create_fstab_config
copy_uboot_to_fs
write_banner
config_first_run
write_uboot_to_disk
clean_work_env
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"
echo
