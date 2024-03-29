#!/bin/bash
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2016 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################
#

#######################################
#
# Build Framework standard script for
#
# rdklogger component

# use -e to fail on any shell issue
# -e is the requirement from Build Framework
set -e


# default PATHs - use `man readlink` for more info
# the path to combined build
export RDK_PROJECT_ROOT_PATH=${RDK_PROJECT_ROOT_PATH-`readlink -m ..`}
export COMBINED_ROOT=$RDK_PROJECT_ROOT_PATH

# path to build script (this script)
export RDK_SCRIPTS_PATH=${RDK_SCRIPTS_PATH-`readlink -m $0 | xargs dirname`}

# path to components sources and target
export RDK_SOURCE_PATH=${RDK_SOURCE_PATH-`readlink -m .`}
export RDK_TARGET_PATH=${RDK_TARGET_PATH-$RDK_SOURCE_PATH}

# fsroot and toolchain (valid for all devices)
export RDK_FSROOT_PATH=${RDK_FSROOT_PATH-`readlink -m $RDK_PROJECT_ROOT_PATH/sdk/fsroot/ramdisk`}
export RDK_TOOLCHAIN_PATH=$RDK_PROJECT_ROOT_PATH/sdk/toolchain/arm-linux-gnueabihf

# default component name
export RDK_COMPONENT_NAME=${RDK_COMPONENT_NAME-`basename $RDK_SOURCE_PATH`}
export RDK_DIR=$RDK_PROJECT_ROOT_PATH

if [ "$XCAM_MODEL" == "XHB1" ] || [ "$XCAM_MODEL" == "XHC3" ]; then
. ${RDK_PROJECT_ROOT_PATH}/build/components/sdk/setenv2
else
export CC=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-gcc
export CXX=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-g++
export AR=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-ar
export LD=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-ld
export NM=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-nm
export RANLIB=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-ranlib
export STRIP=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-strip
export LINK=${RDK_TOOLCHAIN_PATH}/bin/arm-linux-gnueabihf-g++
fi
# parse arguments
INITIAL_ARGS=$@

function usage()
{
    set +x
    echo "Usage: `basename $0` [-h|--help] [-v|--verbose] [action]"
    echo "    -h    --help                  : this help"
    echo "    -v    --verbose               : verbose output"
    echo "    -p    --platform  =PLATFORM   : specify platform for rdklogger"
    echo
    echo "Supported actions:"
    echo "      configure, clean, build (DEFAULT), rebuild, install"
}

# options may be followed by one colon to indicate they have a required argument
if ! GETOPT=$(getopt -n "build.sh" -o hvp: -l help,verbose,platform: -- "$@")
then
    usage
    exit 1
fi

eval set -- "$GETOPT"

while true; do
  case "$1" in
    -h | --help ) usage; exit 0 ;;
    -v | --verbose ) set -x ;;
    -p | --platform ) CC_PLATFORM="$2" ; shift ;;
    -- ) shift; break;;
    * ) break;;
  esac
  shift
done

ARGS=$@

# functional modules
function configure()
{
    pd=`pwd`
    cd ${RDK_SOURCE_PATH}
    aclocal
    libtoolize --automake
    autoheader
    automake --foreign --add-missing
    rm -f configure
    autoconf
    echo "  CONFIG_MODE = $CONFIG_MODE"
        
    configure_options=" "
    configure_options="--host=arm-linux --target=arm-linux"
    configure_options="$configure_options  --enable-rfctool --enable-tr181set=yes --enable-rdkc=yes"

    export cjson_CFLAGS="-I$RDK_PROJECT_ROOT_PATH/opensource/include/cjson"
    export cjson_LIBS="-L$RDK_PROJECT_ROOT_PATH/opensource/lib/ -lcjson"

    ./configure --prefix=${RDK_FSROOT_PATH}/usr --sysconfdir=${RDK_FSROOT_PATH}/etc $configure_options
    cd $pd
}

function clean()
{
    pd=`pwd`
    dnames="${RDK_SOURCE_PATH}"
    for dName in $dnames
    do
        cd $dName
        if [ -f Makefile ]; then
                make distclean-am
                make clean
        fi
        rm -f configure;
        rm -rf aclocal.m4 autom4te.cache config.log config.status libtool
        find . -iname "Makefile.in" -exec rm -f {} \;
        find . -iname "Makefile" | xargs rm -f
        ls cfg/* | grep -v "Makefile.am" | xargs rm -f
        cd $pd
    done
}

function build()
{
    cd ${RDK_SOURCE_PATH}
    make
}

function rebuild()
{
    clean
    configure
    build
}

function install()
{
    mkdir -p $RDK_FSROOT_PATH/lib/rdk/
    cp $RDK_PROJECT_ROOT_PATH/rfc/getRFC.sh $RDK_FSROOT_PATH/lib/rdk/
    cp $RDK_PROJECT_ROOT_PATH/rfc/isFeatureEnabled.sh $RDK_FSROOT_PATH/lib/rdk/
    cp $RDK_PROJECT_ROOT_PATH/rfc/RFCbase.sh $RDK_FSROOT_PATH/lib/rdk/
    cp $RDK_PROJECT_ROOT_PATH/rfc/RFCpostprocess.sh $RDK_FSROOT_PATH/lib/rdk/
    cp $RDK_PROJECT_ROOT_PATH/rfc/rfc.properties $RDK_FSROOT_PATH/etc/rfc.properties
    cp $RDK_PROJECT_ROOT_PATH/rfc/RfcRebootCronschedule.sh $RDK_FSROOT_PATH/lib/rdk/
    cp $RDK_PROJECT_ROOT_PATH/rfc/RFC_Reboot.sh $RDK_FSROOT_PATH/lib/rdk/
    cp $RDK_PROJECT_ROOT_PATH/rfc/rfcInit.sh $RDK_FSROOT_PATH/lib/rdk/
    cd ${RDK_SOURCE_PATH}
    make install
}


# run the logic

#these args are what left untouched after parse_args
HIT=false

for i in "$ARGS"; do
    case $i in
        configure)  HIT=true; configure ;;
        clean)      HIT=true; clean ;;
        build)      HIT=true; build ;;
        rebuild)    HIT=true; rebuild ;;
        install)    HIT=true; install ;;
        *)
            #skip unknown
        ;;
    esac
done

# if not HIT do build by default
if ! $HIT; then
  build
fi

