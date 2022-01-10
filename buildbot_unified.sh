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

export WITHOUT_CHECK_API=true
export WITH_SU=false
export OUT_DIR_COMMON_BASE=~/gsi_out

prep_build() {
    echo "Preparing local manifests"
    #repo init -u https://github.com/Vgdn1942/android.git -b lineage-19.0
    mkdir -p .repo/local_manifests
    cp ./lineage_build_unified/local_manifests_${MODE}/*.xml .repo/local_manifests
    cp ./lineage_build_unified/bv9500plus/local_manifests/*.xml .repo/local_manifests
    rm -f ./lineage_patches_unified/patches_treble/system_core/0001-Revert-init-Add-vendor-specific-initialization-hooks.patch
    rm -f ./lineage_patches_unified/patches_treble_phh/platform_frameworks_base/0006-Support-samsung-Pie-and-Q-light-hal.patch
    rm -f ./lineage_patches_unified/patches_treble_phh/platform_frameworks_base/0009-HOME-deserves-to-wake-up-devices-just-as-well-as-bac.patch # Conflict twelve-camera-button
    rm -f ./lineage_patches_unified/patches_treble_phh/platform_frameworks_base/0024-Revert-Switch-long-press-power-behavior-in-AOSP.patch
    rm -f ./lineage_patches_unified/patches_treble_phh/platform_packages_apps_Bluetooth/0001-On-Samsung-devices-we-need-to-tell-Audio-HAL-if-we-r.patch
    rm -f ./lineage_patches_unified/patches_platform/frameworks_base/0006-UI-Revive-navbar-layout-tuning-via-sysui_nav_bar-tun.patch
    rm -f ./lineage_patches_unified/patches_platform/frameworks_base/0020-SystemUI-Expose-legacy-Wi-Fi-and-cellular-data-QS-ti.patch
    rm -f ./lineage_patches_unified/patches_platform/frameworks_base/0021-SystemUI-Allow-Wi-Fi-cell-tiles-to-co-exist-with-pro.patch # Temporary
    rm -f ./lineage_patches_unified/patches_platform/packages_apps_Settings/9999-TEMP-Settings-Hack-in-LiveDisplay-entrypoint.patch
    cp -r ./lineage_build_unified/bv9500plus/lineage_patches_unified/0013-Make-rounded-corners-padding-overridable-with-persis.patch \
        ./lineage_patches_unified/patches_treble_phh/platform_frameworks_base/
    rm -rf ./device/phh/treble/miravision
    echo ""

    echo "Syncing repos"
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
    echo ""

    echo "Setting up build environment"
    source build/envsetup.sh &> /dev/null
    mkdir -p $BUILD_OUTPUT
    echo ""

    repopick -t android-12.0.0_r26
    repopick -t twelve-touchscreen-gestures
    repopick -t twelve-FlipFlap
    repopick -t twelve-buttons
    repopick -t twelve-camera-button
    repopick -t twelve-navbar-runtime-toggle
    repopick -t twelve-lights
    repopick -t twelve-statusbar-brightness-and-qs-slider
    #repopick -t twelve-proximity-check
    #repopick -t twelve-powermenu
    #repopick -Q "status:open+project:LineageOS/android_packages_apps_AudioFX+branch:lineage-19.0"
    repopick -Q "status:open+project:LineageOS/android_packages_apps_Etar+branch:lineage-19.0+NOT+317685"
    repopick -Q "status:open+project:LineageOS/android_packages_apps_Trebuchet+branch:lineage-19.0+NOT+317783+NOT+318387+NOT+318747"
    repopick 318283 # overlay: core: Remove accent color overrides
    repopick 317788 # overlay: Enable monet

    cd frameworks/native
    git revert 340882c --no-edit # Plumb attribution tag to Sensor Service
    cd ../..
}

gms_patches() {
    NOW=$PWD
    cd vendor/partner_gms
    git clean -fdx; git reset --hard
    for patch in $NOW/lineage_build_unified/bv9500plus/gms_patches/*.patch; do
        if git apply --check $patch; then
            git am $patch
        elif patch -f -p1 --dry-run < $patch > /dev/null; then
            #This will fail
            git am $patch || true
            patch -f -p1 < $patch
            git add -u
            git am --continue
        else
            echo "Failed applying $patch"
        fi
    done
    cd ../..
}

overlay_patches() {
    NOW=$PWD
    cd vendor/hardware_overlay
    git clean -fdx; git reset --hard
    for patch in $NOW/lineage_build_unified/bv9500plus/overlay_patches/*.patch; do
        if git apply --check $patch; then
            git am $patch
        elif patch -f -p1 --dry-run < $patch > /dev/null; then
            #This will fail
            git am $patch || true
            patch -f -p1 < $patch
            git add -u
            git am --continue
        else
            echo "Failed applying $patch"
        fi
    done
    cd ../..
}

apply_patches_personal() {
    echo "Applying patch personal ${1}"
    bash $PWD/../treble_experimentations/apply-patches.sh ./lineage_build_unified/${1}
}

apply_patches() {
    echo "Applying patch group ${1}"
    bash $PWD/../treble_experimentations/apply-patches.sh ./lineage_patches_unified/${1}
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
    rm lineage_treble_a*.mk
    cd ../../..
    tar -xf ./lineage_build_unified/bv9500plus/miravision.tar.gz -C ./device/phh/treble/
}

build_device() {
    brunch ${1}
    mv $OUT/lineage-*.zip $BUILD_OUTPUT/lineage-19.0-$BUILD_DATE-UNOFFICIAL-${1}$($PERSONAL && echo "-personal" || echo "").zip
}

build_treble() {
    case "${1}" in
        ("A64B") TARGET=treble_a64_bvS;;
        ("A64BG") TARGET=treble_a64_bgS;;
        ("64B") TARGET=treble_arm64_bvS;;
        ("64BG") TARGET=treble_arm64_bgS;;
        ("bv9500plus") TARGET=bv9500plus;;
        (*) echo "Invalid target - exiting"; exit 1;;
    esac
    IMAGE_NAME=lineage-19.0-$BUILD_DATE-UNOFFICIAL-${TARGET}$(${PERSONAL} && echo "-personal" || echo "")
    lunch lineage_${TARGET}-userdebug
    make installclean
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
    gms_patches
    overlay_patches
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

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""
