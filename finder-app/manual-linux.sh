#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo... NOT!

set -euo pipefail

OUTDIR=${1:-/tmp/aeld}
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname "$0"))
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-

mkdir -p "${OUTDIR}" || { echo "Failed to create directory ${OUTDIR}"; exit 1; }

cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux" ]; then
    echo "Cloning Linux kernel source..."
    git clone "${KERNEL_REPO}" --depth 1 --branch "${KERNEL_VERSION}" linux
fi

cd linux
echo "Building Linux kernel..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j$(nproc)

echo "Kernel build complete. Copying Image to ${OUTDIR}"
cp -v arch/${ARCH}/boot/Image "${OUTDIR}/"

echo "Creating the staging directory for the root filesystem"
if [ -d "${OUTDIR}/rootfs" ]; then
    sudo rm -rf "${OUTDIR}/rootfs"
fi
mkdir -p "${OUTDIR}/rootfs"

# Build busybox
cd "${OUTDIR}"
if [ ! -d busybox ]; then
    git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
else
    cd busybox
fi

echo "Creating init script..."
cat <<'EOF' >"${OUTDIR}/rootfs/init"
#!/bin/sh
# Simple init script
mount -t proc none /proc
mount -t sysfs none /sys
# Run the shell if no arguments
exec /bin/sh
EOF
chmod +x "${OUTDIR}/rootfs/init"

echo "Configuring and building BusyBox..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install CONFIG_PREFIX="${OUTDIR}/rootfs"

echo "Cross-compiling writer application..."
${CROSS_COMPILE}gcc -o writer "${FINDER_APP_DIR}/writer.c"
if [ ! -f writer ]; then
    echo "Compilation of writer application failed."
    exit 1
fi

# Create necessary directories including home
echo "Setting up root filesystem directories..."
cd "${OUTDIR}/rootfs"
mkdir -pv {bin,sbin,etc,proc,sys,usr/{bin,sbin},lib,home}

# Now that home exists, copy the finder scripts and executables
echo "Adding finder application and scripts..."

if [ -d "home" ]; then
    cp -v "${FINDER_APP_DIR}"/{finder.sh,finder-test.sh,conf/username.txt,conf/assignment.txt,autorun-qemu.sh} home/
    # Correct the path within finder-test.sh
    sed -i 's|../conf/assignment.txt|conf/assignment.txt|' home/finder-test.sh
else
    echo "Error: home directory not found in the root filesystem."
fi

# Create initramfs
echo "Creating initramfs..."
cd "${OUTDIR}/rootfs"
find . | cpio -H newc -o | gzip > "${OUTDIR}/initramfs.cpio.gz"

echo "Build and root filesystem setup complete."
