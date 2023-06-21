
## Building PHH-based LineageOS GSIs ##

To get started with building LineageOS GSI, you'll need to get familiar with [Git and Repo](https://source.android.com/source/using-repo.html), and set up your environment by referring to [LineageOS Wiki](https://wiki.lineageos.org/devices/redfin/build) (mainly "Install the build packages") and [How to build a GSI](https://github.com/phhusson/treble_experimentations/wiki/How-to-build-a-GSI%3F).

First, open a new Terminal window, which defaults to your home directory. Create a new working directory for your LineageOS build and navigate to it:

    mkdir lineage-19.x-build-gsi; cd lineage-19.x-build-gsi

Clone both this and the patches repos:

    git clone https://github.com/Vgdn1942/lineage_build_unified.git -b lineage-19.1
    cp lineage_build_unified/mk-treble .

Finally, start the build script - for example, to build for all supported archs:

    ./mk-treble -s

Be sure to update the cloned repos from time to time!

---

Note: VNDKLite and Secure targets are generated from built images instead of source-built - refer to [sas-creator](https://github.com/AndyCGYan/sas-creator).

---

This script is also used to make device-specific and/or personal builds. To do so, understand the script, and try the `device` and `personal` keywords.
