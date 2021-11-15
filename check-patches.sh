#!/bin/bash

check_patches_personal() {
    echo "Applying patch personal ${1}"
    bash $PWD/../treble_experimentations/check-patches.sh ./lineage_build_unified/${1}
}

check_patches_personal bv9500plus/patches

