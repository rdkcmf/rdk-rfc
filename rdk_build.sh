#!/bin/bash
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2018 RDK Management
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

#######################################
#
# Build Framework standard script for
#
# MediaFramework component

# use -e to fail on any shell issue
# -e is the requirement from Build Framework
set -e

# default component name
export RDK_COMPONENT_NAME=${RDK_COMPONENT_NAME-`basename $RDK_SOURCE_PATH`}

# default PATHs - use `man readlink` for more info
# the path to combined build
export RDK_PROJECT_ROOT_PATH=${RDK_PROJECT_ROOT_PATH-`readlink -m ..`}
export COMBINED_ROOT=$RDK_PROJECT_ROOT_PATH

# path to build script (this script)
export RDK_SCRIPTS_PATH=${RDK_SCRIPTS_PATH-`readlink -m $0 | xargs dirname`}

# path to components sources and target
export RDK_SOURCE_PATH=${RDK_SOURCE_PATH-$RDK_SCRIPTS_PATH}
export RDK_TARGET_PATH=${RDK_TARGET_PATH-$RDK_SOURCE_PATH}

# fsroot and toolchain (valid for all devices)
export RDK_FSROOT_PATH=${RDK_FSROOT_PATH-`readlink -m $RDK_PROJECT_ROOT_PATH/sdk/fsroot/ramdisk`}
export RDK_TOOLCHAIN_PATH=${RDK_TOOLCHAIN_PATH-`readlink -m $RDK_PROJECT_ROOT_PATH/sdk/toolchain/staging_dir`}


if [[ "$RDK_PLATFORM_SOC" == "broadcom" ]] ; then
    export BUILDS_DIR=$RDK_PROJECT_ROOT_PATH
    export DEFAULT_HOST=mipsel-linux
fi

export IARM_PATH=$BUILDS_DIR/iarmbus
export OPENSRC=$RDK_PROJECT_ROOT_PATH/opensource
export cjson_CFLAGS='-I${OPENSRC}/lib/cjson/include'
export cjson_LIBS='-L${OPENSRC}/lib -lcjson'

# component-specific vars
export FSROOT=${RDK_FSROOT_PATH}
export TOOLCHAIN_DIR=${RDK_TOOLCHAIN_PATH}

#Set the Path and Export Variables
if [ $RDK_PLATFORM_SOC = "intel" ]; then
    export CC=$RDK_PROJECT_ROOT_PATH/sdk/toolchain/staging_dir/bin/i686-cm-linux-gcc
    export CXX=$RDK_PROJECT_ROOT_PATH/sdk/toolchain/staging_dir/bin/i686-cm-linux-g++
    export CROSS_TOOLCHAIN=$TOOLCHAIN_DIR
elif [ $RDK_PLATFORM_SOC = "broadcom" ]; then
    echo "building for ${RDK_PLATFORM_DEVICE}..."
    export WORK_DIR=$BUILDS_DIR/work${RDK_PLATFORM_DEVICE^^}
    . $WORK_DIR/../build_scripts/setBCMenv.sh
    
    CROSS_COMPILE=mipsel-linux
    export CC=$CROSS_COMPILE-gcc
    export CXX=$CROSS_COMPILE-g++
fi

# parse arguments
INITIAL_ARGS=$@


function usage()
{
    set +x
    echo "Usage: `basename $0` [-h|--help] [-v|--verbose] [action]"
    echo "    -h    --help                  : this help"
    echo "    -v    --verbose               : verbose output"
    echo
    echo "Supported actions:"
    echo "      configure, clean, build (DEFAULT), rebuild, install"
}

# options may be followed by one colon to indicate they have a required argument
if ! GETOPT=$(getopt -n "rdk_build.sh" -o hvk -l help,verbose -- "$@")
then
    usage
    exit 1
fi

eval set -- "$GETOPT"

while true; do
  case "$1" in
    -h | --help ) usage; exit 0 ;;
    -v | --verbose ) set -x ;;
    -- ) shift; break;;
    * ) break;;
  esac
  shift
done

ARGS=$@


# component-specific vars
export FSROOT=$RDK_FSROOT_PATH


# functional modules

function configure()
{
    pd=`pwd`
    cd ${RDK_SOURCE_PATH}
    autoreconf -f -i
    echo "  CONFIG_MODE = $CONFIG_MODE"
    
    configure_options=" "
    if [ "x$DEFAULT_HOST" != "x" ]; then
	echo "DEFAULT_HOST is $DEFAULT_HOST"
        configure_options="--host $DEFAULT_HOST"
    else
	echo "NO DEFAULT_HOST is defined"
    fi

    configure_options="$configure_options --enable-shared --with-pic"
    generic_options="$configure_options"
    
    extraenablers="--enable-rfctool"

    if [ "$RDK_PLATFORM_DEVICE" != "rng150" ] ; then
        echo "Add tr181Set tool	"
        extraenablers="$extraenablers --enable-tr181set"
    fi
     
    if [ "$RDK_PLATFORM_SOC" = "stm" ];then
        ./configure --prefix=/usr $configure_options $extraenablers
    else
        ./configure --prefix=${RDK_FSROOT_PATH}/usr $configure_options $extraenablers
    fi
    cd $pd
}

function clean()
{
    pd=`pwd`
    dName="${RDK_SOURCE_PATH}"
    cd $dName
    if [ -f Makefile ]; then
        make distclean
    fi
    rm -f configure;
    rm -rf aclocal.m4 autom4te.cache config.log config.status libtool
    find . -iname "Makefile.in" -exec rm -f {} \; 
    if [ "$RDK_PLATFORM_SOC" = "stm" ];then
        find . -name Makefile | grep -v "aes" | xargs rm -rf
    else
        find . -iname "Makefile" -exec rm -f {} \; 
    fi
    ls cfg/* | grep -v "Makefile.am" | xargs rm -f
    cd $pd
}

function build()
{
    cd ${RDK_SOURCE_PATH}
    make
    #make install
    #make -C qamsource
    #make -C snmp
}

function rebuild()
{
    clean
    configure
    build
}

function install()
{
    cd ${RDK_SOURCE_PATH}

    if [ "$RDK_PLATFORM_SOC" = "stm" ];then
       make install DESTDIR=${RDK_FSROOT_PATH}
    else
       make install
    fi
    cp utils/rfctool $FSROOT/usr/bin
    if [ "x${RDK_PLATFORM_DEVICE^^}" != "xRNG150" ]; then
        cp utils/tr181Set $FSROOT/usr/bin
    fi
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
  rebuild
fi
