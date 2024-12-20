#!/bin/bash
#
# Copyright (C) 2023 Paranoid Android
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

### Setup
DUMP=
MY_DIR="${BASH_SOURCE%/*}"
SRC_ROOT="${MY_DIR}/../../.."
TMP_DIR=$(mktemp -d)
EXTRACT_KERNEL=true
declare -a MODULE_FOLDERS=("vendor_ramdisk" "vendor_dlkm" "system_dlkm")

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-kernel )
                EXTRACT_KERNEL=false
                ;;
        * )
                DUMP="${1}"
                ;;
    esac
    shift
done

[ -f "${MY_DIR}/Module.symvers" ] || touch "${MY_DIR}/Module.symvers"
[ -f "${MY_DIR}/System.map" ] || touch "${MY_DIR}/System.map"

# Check if dump is specified and exists
if [ -z "${DUMP}" ]; then
    echo "Please specify the dump!"
    exit 1
elif [ ! -d "${DUMP}" ]; then
    echo "Unable to find dump at ${DUMP}!"
    exit 1
fi

echo "Extracting files from ${DUMP}:"

### Kernel
if ${EXTRACT_KERNEL}; then
    echo "Extracting boot image.."
    ${SRC_ROOT}/system/tools/mkbootimg/unpack_bootimg.py \
        --boot_img "${DUMP}/boot.img" \
        --out "${TMP_DIR}/boot.out" > /dev/null
    cp -f "${TMP_DIR}/boot.out/kernel" ${MY_DIR}/
    echo "  - Image"
fi

### DTBS
# Cleanup / Preparation
rm -rf "${MY_DIR}/dtb"
mkdir "${MY_DIR}/dtb"

echo "Extracting vendor_boot image..."
${SRC_ROOT}/system/tools/mkbootimg/unpack_bootimg.py \
    --boot_img "${DUMP}/vendor_boot.img" \
    --out "${TMP_DIR}/vendor_boot.out" > /dev/null

curl -sSL "https://raw.githubusercontent.com/PabloCastellano/extract-dtb/master/extract_dtb/extract_dtb.py" > ${TMP_DIR}/extract_dtb.py

# Copy
python3 "${TMP_DIR}/extract_dtb.py" "${TMP_DIR}/vendor_boot.out/dtb" -o "${TMP_DIR}/dtb" > /dev/null
find "${TMP_DIR}/dtb" -type f -name "*.dtb" \
    -exec cp {} "${MY_DIR}/dtb" \; \
    -exec printf "  - dtb/" \; \
    -exec basename {} \;
cp -f "${DUMP}/dtbo.img" "${MY_DIR}/dtbo.img"
echo "  - dtbo.img"

### Modules
# Cleanup / Preparation
for MODULE_FOLDER in "${MODULE_FOLDERS[@]}"; do
    rm -rf "${MY_DIR}/${MODULE_FOLDER}"
    mkdir "${MY_DIR}/${MODULE_FOLDER}"
done

# Copy
for MODULE_FOLDER in "${MODULE_FOLDERS[@]}"; do
    MODULE_SRC="${DUMP}/${MODULE_FOLDER}"

    if [ "${MODULE_FOLDER}" == "vendor_ramdisk" ]; then
        lz4 -qd "${TMP_DIR}/vendor_boot.out/vendor_ramdisk00" "${TMP_DIR}/vendor_ramdisk.cpio"
        7z x "${TMP_DIR}/vendor_ramdisk.cpio" -o"${TMP_DIR}/vendor_ramdisk" > /dev/null
        MODULE_SRC="${TMP_DIR}/vendor_ramdisk"
    fi

    if [ "${MODULE_FOLDER}" == "system_dlkm" ]; then
        MODULE_SRC="${DUMP}/system_dlkm/lib/modules/6.1.25-android14-11-maybe-dirty"
    fi

    [ -d "${MODULE_SRC}" ] || { echo "Source ${MODULE_SRC} not found or empty! Skipping ${MODULE_FOLDER}."; continue; }

    if [ "${MODULE_FOLDER}" == "system_dlkm" ]; then
        # Only for system_dlkm, copy everything inside the specified folder
        echo "Copying everything from ${MODULE_SRC} to ${MY_DIR}/${MODULE_FOLDER}..."
        cp -r "${MODULE_SRC}/." "${MY_DIR}/${MODULE_FOLDER}/"
    else
        # For vendor_dlkm and vendor_ramdisk, process as before
        echo "Copying modules from ${MODULE_SRC} to ${MY_DIR}/${MODULE_FOLDER}..."
        find "${MODULE_SRC}/lib/modules" -type f \
            -exec cp {} "${MY_DIR}/${MODULE_FOLDER}/" \; \
            -exec printf "  - ${MODULE_FOLDER}/" \; \
            -exec basename {} \;
    fi
done

# Clear temp dir
rm -rf "${TMP_DIR}"
