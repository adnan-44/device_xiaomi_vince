#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

# Required!
DEVICE=vince
VENDOR=xiaomi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc)
            sed -i 's/fps_hal/vendor.fps_hal/' "${2}"
            sed -i 's/group.*/& uhid/' "${2}"
            ;;
        product/etc/permissions/vendor.qti.hardware.data.connection-V1.0-java.xml|product/etc/permissions/vendor.qti.hardware.data.connection-V1.1-java.xml)
            sed -i 's/version="2.0"/version="1.0"/g' "${2}"
            ;;
        product/lib64/libdpmframework.so)
            for LIBSHIM_DPMFRAMEWORK in $(grep -L "libshim_dpmframework.so" "${2}"); do
                "${PATCHELF}" --add-needed "libshim_dpmframework.so" "${2}"
            done
            ;;
        vendor/lib/mediadrm/libwvdrmengine.so|vendor/lib64/mediadrm/libwvdrmengine.so)
            "${PATCHELF}" --replace-needed "libprotobuf-cpp-lite.so" "libprotobuf-cpp-lite-v29.so" "${2}"
            ;;
        vendor/lib64/libsettings.so)
            "${PATCHELF}" --replace-needed "libprotobuf-cpp-full.so" "libprotobuf-cpp-full-v29.so" "${2}"
            ;;
        vendor/lib64/libwvhidl.so)
            "${PATCHELF}" --replace-needed "libprotobuf-cpp-lite.so" "libprotobuf-cpp-lite-v29.so" "${2}"
            ;;
        vendor/lib64/libvendor.goodix.hardware.fingerprint@1.0-service.so)
            "${PATCHELF_0_8}" --remove-needed "libprotobuf-cpp-lite.so" "${2}"
            ;;
        vendor/lib/libmmcamera2_iface_modules.so)
            # Always set 0 (Off) as CDS mode in iface_util_set_cds_mode
            sed -i -e 's|\x1d\xb3\x20\x68|\x1d\xb3\x00\x20|g' "${2}"
            PATTERN_FOUND=$(hexdump -ve '1/1 "%.2x"' "${2}" | grep -E -o "1db30020" | wc -l)
            if [ $PATTERN_FOUND != "1" ]; then
                echo "Critical blob modification weren't applied on ${2}!"
                exit;
            fi
            ;;
    esac
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
