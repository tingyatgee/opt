#!/bin/bash

MYSELF=$0

function destory_myself() {
    rm -f $MYSELF /etc/part_size
    mv -f /etc/rc.local.orig /etc/rc.local
}

if [ ! -f /etc/part_size ];then
    echo "/etc/part_size 不存在！"
    destory_myself
    exit 1
fi

# 找到 root 所在的分区
ROOT_PTNAME=$(df / | tail -n1 | awk '{print $1}' | awk -F '/' '{print $3}')
if [ "$ROOT_PTNAME" == "" ];then
    echo "找不到根文件系统对应的分区!"
    destory_myself
    exit 1
fi

# 找到分区所在的磁盘, 仅支持 mmcblk?p?  nvme?n?p? sd?? hd?? vd??等格式
case $ROOT_PTNAME in 
       mmcblk?p[1-4]) DISK_NAME=$(echo $ROOT_PTNAME | awk '{print substr($1, 1, length($1)-2)}');;
           nvme?n?p?) DISK_NAME=$(echo $ROOT_PTNAME | awk '{print substr($1, 1, length($1)-2)}');;
   [hsv]d[a-z][1-9]*) DISK_NAME=$(echo $ROOT_PTNAME | awk '{print substr($1, 1, length($1)-1)}');;
		   *) echo "无法识别 $ROOT_PTNAME 的磁盘类型!"
		      destory_myself
		      exit 1
		   ;;
esac
echo "Root disk name: ${DISK_NAME}"

# 第一次运行，需要修复磁盘大小
printf 'f\n' | parted ---pretend-input-tty /dev/${DISK_NAME} print || fail=1
if [ "$fail" == "1" ];then
	echo "分区表未修复！需要手动执行 $MYSELF"
	exit 1
fi

CURRENT_PT_CNT=$(parted /dev/${DISK_NAME} print | awk '$1~/[1-9]+/ {print $1}' | wc -l)
if [ "$CURRENT_PT_CNT" != "2" ];then
    echo "现存分区数量不为2,放弃!"
    destory_myself
    exit 1
fi

DISK_TOTAL_B=$(lsblk -b -l | grep disk | grep -E "^${DISK_NAME}\s" | awk '{print $4}')
SKIP_MiB=$(awk '{print $1}' /etc/part_size)
BOOT_MiB=$(awk '{print $2}' /etc/part_size)
ROOTFS_MiB=$(awk '{print $3}' /etc/part_size)

USED_MiB=$((SKIP_MiB + BOOT_MiB + ROOTFS_MiB + 1))
AVAIABLE_MiB=$(( (DISK_TOTAL_B / 1024 / 1024) - USED_MiB))

echo "Disk total bytes: ${DISK_TOTAL_B}"
echo "Used MBytes: ${USED_MiB}"
echo "Avaiable MBytes: ${AVAIABLE_MiB}"

if [[ $AVAIABLE_MiB -lt $ROOTFS_MiB ]];then
    echo "磁盘空闲空间不满足扩展分区的要求！"
    destory_myself
    exit 1
fi

TARGET_ROOTFS2_FSTYPE=btrfs
TARGET_SHARED_FSTYPE=btrfs

echo "create new partition ... "
START_P3=$(( (SKIP_MiB + BOOT_MiB + ROOTFS_MiB) * 1024 * 1024 ))
END_P3=$((ROOTFS_MiB * 1024 * 1024 + START_P3 -1))
parted /dev/${DISK_NAME} mkpart primary ${TARGET_ROOTFS2_FSTYPE} ${START_P3}b ${END_P3}b

START_P4=$((END_P3 + 1))
parted /dev/${DISK_NAME} mkpart primary "${TARGET_SHARED_FSTYPE}" ${START_P4}b "100%"
echo "done"
parted /dev/${DISK_NAME} unit MiB print

# mkfs
case $DISK_NAME in 
   mmcblk*) PT_PRE=${DISK_NAME}p
	    LB_PRE="MMC_"
	    ;;
     nvme*) PT_PRE=${DISK_NAME}p
	    LB_PRE="NVME_"
	    ;;
	 *) PT_PRE=${DISK_NAME}
	    LB_PRE=""
	    ;;
esac
echo "create rootfs2 filesystem ... "
mkdir -p /mnt/${PT_PRE}3
case $TARGET_ROOTFS2_FSTYPE in
	xfs) mkfs.xfs   -f -L "${LB_PRE}ROOTFS2" "/dev/${PT_PRE}3"
	     mount -t xfs     "/dev/${PT_PRE}3" "/mnt/${PT_PRE}3"
	     ;;
      btrfs) mkfs.btrfs -f -L "${LB_PRE}ROOTFS2" "/dev/${PT_PRE}3" 
	     mount -t btrfs   "/dev/${PT_PRE}3" "/mnt/${PT_PRE}3"
	     ;; 
	  *) mkfs.ext4  -F -L "${LB_PRE}ROOTFS2" "/dev/${PT_PRE}3"
	     mount -t ext4    "/dev/${PT_PRE}3" "/mnt/${PT_PRE}3"
	     ;;
esac
echo "done"

echo "create shared filesystem ... "
mkdir -p /mnt/${PT_PRE}4
case $TARGET_SHARED_FSTYPE in
	xfs) mkfs.xfs   -f -L "${LB_PRE}SHARED" "/dev/${PT_PRE}4"
	     mount -t xfs     "/dev/${PT_PRE}4" "/mnt/${PT_PRE}4"
	     ;;
      btrfs) mkfs.btrfs -f -L "${LB_PRE}SHARED" "/dev/${PT_PRE}4"
	     mount -t btrfs   "/dev/${PT_PRE}4" "/mnt/${PT_PRE}4"
	     ;; 
	  *) mkfs.ext4  -F -L "${LB_PRE}SHARED" "/dev/${PT_PRE}4"
	     mount -t ext4    "/dev/${PT_PRE}4" "/mnt/${PT_PRE}4"
	     ;;
esac
echo "done"

echo "clean ... "
destory_myself
echo "done"
echo "The end."
