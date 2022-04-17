#!/bin/bash
echo ""
echo "LineageOS 19.x Unified Buildbot"
echo "Executing in 5 seconds - CTRL-C to exit"
echo ""
sleep 5

if [ $# -lt 2 ]
then
    echo "Not enough arguments - exiting"
    echo ""
    exit 1
fi

MODE=${1}
if [ ${MODE} != "device" ] && [ ${MODE} != "treble" ]
then
    echo "Invalid mode - exiting"
    echo ""
    exit 1
fi

NOSYNC=false
PERSONAL=false
for var in "${@:2}"
do
    if [ ${var} == "nosync" ]
    then
        NOSYNC=true
    fi
    if [ ${var} == "personal" ]
    then
        PERSONAL=true
    fi
done

# Abort early on error
set -eE
trap '(\
echo;\
echo \!\!\! An error happened during script execution;\
echo \!\!\! Please check console output for bad sync,;\
echo \!\!\! failed patch application, etc.;\
echo\
)' ERR

START=`date +%s`
BUILD_DATE="$(date +%Y%m%d)"
BUILD_OUTPUT=~/GSI_treble_build/build-output

export WITH_SU=false
export WITH_GAPPS=true
#export OUT_DIR_COMMON_BASE=~/gsi_out
export PATH=$PATH:~/bin

prep_build() {
    echo "Preparing local manifests"
    #repo init -u https://github.com/Vgdn1942/android.git -b lineage-19.1
    #repo init -u https://github.com/AndyCGYan/android.git -b lineage-19.1
    #repo init -u https://github.com/LineageOS/android.git -b lineage-19.1
    mkdir -p .repo/local_manifests
    cp ./lineage_build_unified/local_manifests/*.xml .repo/local_manifests

    rm -rf ./lineage_build_unified/bv9500plus/patches_andy_yan
    mkdir -p ./lineage_build_unified/bv9500plus/patches_andy_yan/frameworks_base
    cp ./lineage_patches_unified/patches_platform_personal/frameworks_base/0003-Disable-FP-lockouts.patch \
        ./lineage_build_unified/bv9500plus/patches_andy_yan/frameworks_base
    cp ./lineage_patches_unified/patches_platform_personal/frameworks_base/0008-Keyguard-UI-Fix-status-bar-quick-settings-margins-an.patch \
        ./lineage_build_unified/bv9500plus/patches_andy_yan/frameworks_base
    cp ./lineage_patches_unified/patches_platform_personal/frameworks_base/0015-UI-Remove-privacy-dot-padding.patch \
        ./lineage_build_unified/bv9500plus/patches_andy_yan/frameworks_base

    rm -f ./lineage_patches_unified/patches_treble/system_core/0001-Revert-init-Add-vendor-specific-initialization-hooks.patch # Back vendor_init
    rm -f ./lineage_patches_unified/patches_platform/frameworks_base/0009-UI-Revive-navbar-layout-tuning-via-sysui_nav_bar-tun.patch # fix bootloop after add lockscreen

    # unneeded patches
    rm -f ./lineage_patches_unified/patches_platform/vendor_partner_gms/0001-SearchLauncher-Adapt-to-Trebuchet.patch
    rm -f ./lineage_patches_unified/patches_platform/vendor_partner_gms/0002-SearchLauncher-Fix-build-on-Sv2.patch
    rm -f ./lineage_patches_unified/patches_platform/frameworks_base/0011-UI-Unblock-alarm-status-bar-icon.patch

    rm -rf ./device/phh/treble/miravision
    echo ""

    echo "Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
    echo ""

    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    mkdir -p $BUILD_OUTPUT
    echo ""

    repopick -Q "status:open+project:LineageOS/android_packages_apps_Trebuchet+branch:lineage-19.1"
    repopick -t twelve-burnin

    repopick 321337 # Deprioritize important developer notifications
    repopick 321338 # Allow disabling important developer notifications
    repopick 321339 # Allow disabling USB notifications
    repopick 326712 # overlay: show all icons in collapsed statusbar
    repopick 327113 # Keystore 2.0: Add CREATION_DATETIME only for Keymint V1 and higher.

    repopick -f 239371 # SystemUI: Switch back to pre P mobile type icon style

    cd frameworks/native
    git revert 340882c64b5944a62b122bbb24f95645c5a0c465 --no-edit # Plumb attribution tag to Sensor Service
    cd ../..

    # fix bootloop after add lockscreen
    cd frameworks/base
    git revert 3d2dc3fd4d9f222259ea0fde745e20524a05e0d0 --no-edit # SystemUI: Implement hide gestural navigation hint bar [1/5]
    cd ../..
}

apply_patches() {
    echo "Applying patch group ${1}"
    bash ./lineage_build_unified/apply_patches.sh ./lineage_patches_unified/${1}
}

apply_patches_personal() {
    echo "Applying personal patch group ${1}"
    bash ./lineage_build_unified/apply_patches.sh ./lineage_build_unified/${1}
}

prep_device() {
    :
}

prep_treble() {
    apply_patches patches_treble_prerequisite
    apply_patches patches_treble_phh
}

finalize_device() {
    :
}

finalize_treble() {
    rm -f device/*/sepolicy/common/private/genfs_contexts
    cd device/phh/treble
    git clean -fdx
    bash generate.sh lineage
    rm lineage_a*.mk
    cd ../../..
    tar -xf ./lineage_build_unified/bv9500plus/miravision.tar.gz -C ./device/phh/treble/
}

build_device() {
    brunch ${1}
    mv $OUT/lineage-*.zip $BUILD_OUTPUT/lineage-19.1-$BUILD_DATE-UNOFFICIAL-${1}$($PERSONAL && echo "-personal" || echo "").zip
}

build_treble() {
    case "${1}" in
        ("A64B") TARGET=a64_bvS;;
        ("A64BG") TARGET=a64_bgS;;
        ("64B") TARGET=arm64_bvS;;
        ("64BG") TARGET=arm64_bgS;;
        ("bv9500plus") TARGET=bv9500plus;;
        (*) echo "Invalid target - exiting"; exit 1;;
    esac
    IMAGE_NAME=lineage-19.1-$BUILD_DATE-UNOFFICIAL-${TARGET}$(${PERSONAL} && echo "-personal" || echo "")
    lunch lineage_${TARGET}-userdebug
    make -j$(nproc --all) installclean
    make -j$(nproc --all) systemimage
    #make -j4 systemimage
    mv $OUT/system.img $BUILD_OUTPUT/${IMAGE_NAME}.img
    xz -c $BUILD_OUTPUT/$IMAGE_NAME.img -T$(nproc --all) > $BUILD_OUTPUT/$IMAGE_NAME.img.xz
    #make vndk-test-sepolicy
}

if ${NOSYNC}
then
    echo "ATTENTION: syncing/patching skipped!"
    echo ""
    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    echo ""
else
    prep_build
    echo "Applying patches"
    prep_${MODE}
    apply_patches patches_platform
    apply_patches patches_${MODE}
    apply_patches_personal bv9500plus/patches
    apply_patches_personal bv9500plus/patches_andy_yan
    if ${PERSONAL}
    then
        apply_patches patches_platform_personal
        apply_patches patches_${MODE}_personal
    fi
    finalize_${MODE}
    echo ""
fi

for var in "${@:2}"
do
    if [ ${var} == "nosync" ] || [ ${var} == "personal" ]
    then
        continue
    fi
    echo "Starting $(${PERSONAL} && echo "personal " || echo "")build for ${MODE} ${var}"
    build_${MODE} ${var}
done
ls $BUILD_OUTPUT | grep 'lineage' || true
du -hs $BUILD_OUTPUT/lineage*

if [ ${MODE} == "treble" ]
then
    echo "OTA timestamp: $START"
    echo ""
fi

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""
