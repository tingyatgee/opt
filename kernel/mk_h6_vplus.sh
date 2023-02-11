#!/bin/bash

echo "========================= begin $0 ================="
source make.env
source public_funcs
init_work_env

PLATFORM=allwinner
SOC=h6
BOARD=vplus
SUBVER=$1

# Kernel image sources
###################################################################
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
check_file ${MODULES_TGZ}
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
check_file ${BOOT_TGZ}
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-allwinner-${KERNEL_VERSION}.tar.gz
check_file ${DTBS_TGZ}
###################################################################

# Openwrt 
OP_ROOT_TGZ="openwrt-armvirt-64-default-rootfs.tar.gz"
OPWRT_ROOTFS_GZ="${PWD}/${OP_ROOT_TGZ}"
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# Target Image
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# patches、scripts
####################################################################
FIRSTRUN_SCRIPT="${PWD}/files/first_run.sh"
BOOT_CMD="${PWD}/files/vplus/boot/boot.cmd"
BOOT_SCR="${PWD}/files/vplus/boot/boot.scr"

BANNER="${PWD}/files/banner"

FMW_HOME="${PWD}/files/firmware"

UBOOT_BIN="${PWD}/files/vplus/u-boot-v2022.04/u-boot-sunxi-with-spl.bin"
WRITE_UBOOT_SCRIPT="${PWD}/files/vplus/u-boot-v2022.04/update-u-boot.sh"

FIRMWARE_TXZ="${PWD}/files/firmware_armbian.tar.xz"
BOOTFILES_HOME="${PWD}/files/bootfiles/allwinner"
####################################################################

check_depends
SKIP_MB=16
BOOT_MB=160
ROOTFS_MB=720
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB))
create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "msdos" "$SKIP_MB" "$BOOT_MB" "fat32" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "fat32" "EMMC_BOOT" "R" "btrfs" "EMMC_ROOTFS1"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "vfat"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"
echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc
extract_rootfs_files
extract_allwinner_boot_files

echo "修改引导分区相关配置 ... "
cd $TGT_BOOT
[ -f $BOOT_CMD ] && cp -v $BOOT_CMD boot.cmd
[ -f $BOOT_SCR ] && cp -v $BOOT_SCR boot.scr
rm -f boot-emmc.cmd boot-emmc.scr
cat > uEnv.txt <<EOF
LINUX=/zImage
INITRD=/uInitrd

#  普通版 1800Mhz
FDT=/dtb/allwinner/sun50i-h6-vplus-cloud.dtb

APPEND=root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd:${ZSTD_LEVEL} console=ttyS0,115200n8 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF
echo "uEnv.txt -->"
echo "======================================================================================"
cat uEnv.txt
echo "======================================================================================"
echo

echo "修改根文件系统相关配置 ... "
cd $TGT_ROOT
create_fstab_config
copy_uboot_to_fs
write_banner
config_first_run
write_uboot_to_disk
clean_work_env
mv $TGT_IMG $OUTPUT_DIR && sync
echo "镜像已生成, 存放在 ${OUTPUT_DIR} 下面"
echo "========================== end $0 ================================"
echo
