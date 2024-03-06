#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo... NOT!
# Additional contributions by Abdul Sabbagh for device tree binaries and library setup.

set -euo pipefail

# a. Handle outdir argument
OUTDIR=${1:-/tmp/aeld}
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname "$0"))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

# b. Create outdir if it doesn't exist
mkdir -p "${OUTDIR}" || { echo "Failed to create directory ${OUTDIR}"; exit 1; }

# c. Build kernel image
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux" ]; then
    echo "Cloning Linux kernel source..."
    git clone "${KERNEL_REPO}" --depth 1 --branch "${KERNEL_VERSION}" linux
fi

cd linux
echo "Building Linux kernel..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j"$(nproc)"

# Additional step by Abdul Sabbagh: build device tree binaries
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs # Build device tree binaries

# d. Copy kernel image to outdir
echo "Kernel build complete. Copying Image to ${OUTDIR}"
cp -v arch/${ARCH}/boot/Image "${OUTDIR}/"

# e. Build root filesystem
echo "Creating the staging directory for the root filesystem"
if [ -d "${OUTDIR}/rootfs" ]; then
    sudo rm -rf "${OUTDIR}/rootfs"
fi
mkdir -p "${OUTDIR}/rootfs"

mkdir -p "${OUTDIR}/rootfs/lib"
mkdir -p "${OUTDIR}/rootfs/lib64"

# Additional steps by Abdul Sabbagh: Setup essential libraries for the root filesystem
cd "${OUTDIR}/rootfs"
PATH_LIBRARY=$(aarch64-none-linux-gnu-gcc -print-sysroot)
cp "${PATH_LIBRARY}/lib/ld-linux-aarch64.so.1" "${OUTDIR}/rootfs/lib"
cp "${PATH_LIBRARY}/lib64/libm.so.6" "${OUTDIR}/rootfs/lib64"
cp "${PATH_LIBRARY}/lib64/libresolv.so.2" "${OUTDIR}/rootfs/lib64"
cp "${PATH_LIBRARY}/lib64/libc.so.6" "${OUTDIR}/rootfs/lib64"

# Build busybox
cd "${OUTDIR}"
if [ ! -d busybox ]; then
    git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
else
    cd busybox
fi

echo "Configuring and building BusyBox..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install CONFIG_PREFIX="${OUTDIR}/rootfs"

# Ensure /home and /home/conf directories exist in rootfs before copying files
echo "Ensuring /home and /home/conf directories exist in rootfs..."
mkdir -p "${OUTDIR}/rootfs/home/conf"

# Cross-compiling writer application
echo "Cross-compiling writer application..."
${CROSS_COMPILE}gcc -o "${OUTDIR}/rootfs/home/writer" "${FINDER_APP_DIR}/writer.c"
if [ ! -f "${OUTDIR}/rootfs/home/writer" ]; then
    echo "Compilation of writer application failed."
    exit 1
fi

# Setting up remaining root filesystem directories
echo "Setting up root filesystem directories..."
cd "${OUTDIR}/rootfs"
mkdir -pv {bin,sbin,etc,proc,sys,usr/{bin,sbin},lib}

# Adding finder application and scripts
echo "Adding finder application, scripts, and configuration files..."
cp -v "${FINDER_APP_DIR}"/finder.sh "${OUTDIR}/rootfs/home/"
cp -v "${FINDER_APP_DIR}"/finder-test.sh "${OUTDIR}/rootfs/home/"
cp -v "${FINDER_APP_DIR}"/autorun-qemu.sh "${OUTDIR}/rootfs/home/"
cp -v "${FINDER_APP_DIR}"/conf/username.txt "${OUTDIR}/rootfs/home/conf/"
cp -v "${FINDER_APP_DIR}"/conf/assignment.txt "${OUTDIR}/rootfs/home/conf/"
# Correct the path within finder-test.sh to reflect new location of configuration files
sed -i 's|../conf/assignment.txt|conf/assignment.txt|' "${OUTDIR}/rootfs/home/finder-test.sh"


# Create an init script in the rootfs directory
cat <<'EOF' >"${OUTDIR}/rootfs/init"
#!/bin/sh
# Simple init script
mount -t proc none /proc
mount -t sysfs none /sys
# Run the shell if no arguments
exec /bin/sh
EOF

# Make the init script executable
chmod +x "${OUTDIR}/rootfs/init"

# h. Create initramfs
echo "Creating initramfs..."
cd "${OUTDIR}/rootfs"
find . | cpio -H newc -o | gzip > "${OUTDIR}/initramfs.cpio.gz"

echo "Build and root filesystem setup complete."
