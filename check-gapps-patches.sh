#!/bin/bash

check_gms_patches() {
    NOW=$PWD
    cd vendor/partner_gms

	for patch in $NOW/lineage_build_unified/bv9500plus/gms_patches/*.patch;do
		if git apply --check $patch;then
			echo "git am $patch"
		else
			echo "Failed applying $patch"
		fi
	done
    cd ../..
}

check_gms_patches
