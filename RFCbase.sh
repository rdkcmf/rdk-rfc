#!/bin/sh
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
#
##################################################################
## Script to perform Remote Feature Control
## Updates the following information in the settop box
##    list of features that are enabled or disabled
##    if feature configuration is effective immediately
##    updates startup parameters for each feature
##    updates the list of variables in a single file
## Author: Ajaykumar/Shakeel/Suraj/Milorad
##################################################################

. /etc/include.properties
. /etc/device.properties


## DEVICE_TYPE definitions from device.properties
##  "$DEVICE_TYPE" = "mediaclient"
##  DEVICE_TYPE=hybrid
##   "$DEVICE_TYPE" == "XHC1"
##   "$DEVICE_TYPE" = "rmfstreamer"
##  "$DEVICE_TYPE" = "broadband"
##

#MN2
if [ "$DEVICE_TYPE" = "broadband" ]; then
    source /etc/log_timestamp.sh  #?
    source /lib/rdk/getpartnerid.sh
    source /lib/rdk/getaccountid.sh
else
# initialize partnerId
    . $RDK_PATH/getPartnerId.sh
# initialize accountId
    . $RDK_PATH/getAccountId.sh

    # initialize accounHash
    if [ "$DEVICE_TYPE" = "XHC1" ]; then
        . $RDK_PATH/getAccountHash.sh
    fi
fi


if [ -z $PERSISTENT_PATH ]; then
    if [ "$DEVICE_TYPE" = "broadband" ]; then
        PERSISTENT_PATH="/nvram"
    elif  [ "$DEVICE_TYPE" = "hybrid" ] || [ "$DEVICE_TYPE" = "mediaclient" ] || [ "$DEVICE_TYPE" = "XHC1" ];then
        PERSISTENT_PATH="/opt"
    else
        PERSISTENT_PATH="/tmp"
    fi
fi

if [ -f $RDK_PATH/utils.sh ]; then
   . $RDK_PATH/utils.sh
fi

# Per QA request, local override is highest priority
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/rfc.properties ]; then
    # Load local RFC configuration
    . $PERSISTENT_PATH/rfc.properties
    rfcState="LOCAL"
else
    # Initially load firmware RFC configuration
    . /etc/rfc.properties
    rfcState="INIT"  # valid values are "INIT", "CONTINUE", "REDO", "LOCAL"
fi

if [ -z $LOG_PATH ]; then
    if [ "$DEVICE_TYPE" = "broadband" ]; then
        LOG_PATH="/rdklogs/logs"
    else
        LOG_PATH="/opt/logs"
    fi
fi


if [ "$DEVICE_TYPE" = "broadband" ]; then
    RFC_LOG_FILE="$LOG_PATH/dcmrfc.log"
else
    RFC_LOG_FILE="$LOG_PATH/rfcscript.log"
fi

if [ -z $RDK_PATH ]; then
    RDK_PATH="/lib/rdk"
fi


if [ -z $RFC_PATH ]; then
    RFC_PATH="$PERSISTENT_PATH/RFC"
fi

if [ ! -d $RFC_PATH ]; then
    mkdir -p $RFC_PATH
fi

# create RAM based folder
if [ -z $RFC_RAM_PATH ]; then
    RFC_RAM_PATH="/tmp/RFC"
fi

if [ ! -d $RFC_RAM_PATH ]; then
    mkdir -p $RFC_RAM_PATH
fi

# create temp folder used for processing json data
RFC_TMP_PATH="$RFC_RAM_PATH/tmp"

if [ ! -d $RFC_TMP_PATH ]; then
    mkdir -p $RFC_TMP_PATH
fi
WAREHOUSE_ENV="$RAMDISK_PATH/warehouse_mode_active"
export PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/sbin:/usr/local/lighttpd/sbin:/usr/local/sbin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/Qt/lib:/usr/local/lib
RFCFLAG="/tmp/.RFCSettingsFlag"



#---------------------------------
# Initialize Variables
#---------------------------------
if [ "$DEVICE_TYPE" = "broadband" ]; then
    RFC_GET="dmcli eRT getv"
    RFC_SET="dmcli eRT setv"
elif [ "$DEVICE_TYPE" = "XHC1" ]; then
    RFC_GET="dmcli -g"
    RFC_SET="dmcli -s"
else
    RFC_GET="tr181 "
    RFC_SET="tr181 -s -t s"
fi

# File to save curl response
FILENAME='/tmp/rfc-parsed.txt'

DCM_PARSER_RESPONSE="/tmp/rfc_configdata.txt"

URL="$RFC_CONFIG_SERVER_URL"
echo "Initial URL: $URL"

# File to save http code
HTTP_CODE="/tmp/rfc_curl_httpcode"
rm -rf $HTTP_CODE

# Cron job file name
current_cron_file="/tmp/cron_list"

if [ "$DEVICE_TYPE" = "broadband" ]; then
    # Timeout value
    timeout=30
else
    timeout=10
fi
# http header
# HTTP_HEADERS='Content-Type: application/json'

## RETRY DELAY in secs
RETRY_DELAY=60
## RETRY COUNT
RETRY_COUNT=3
DIRECT_BLOCK_FILENAME="/tmp/.lastdirectfail_rfc"
default_IP=$DEFAULT_IP

# store the working copy to VARFILE
VARFILE="$RFC_TMP_PATH/rfcVariable.ini"
VARIABLEFILE="$RFC_PATH/rfcVariable.ini"

#Xconf tr69 paramters
XCONF_SELECTOR_TR181_NAME="Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.XconfSelector"
XCONF_URL_TR181_NAME="Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.XconfUrl"

#Xconf URL names for reference only, they are configured in Xconf
# PROD_XCONF_URL="https://xconf.xcal.tv/featureControl/getSettings"
# CI_XCONF_URL="https://ci.xconfds.coast.xcal.tv/featureControl/getSettings"
# AUTO_XCONF_URL="https://rdkautotool.ccp.xcal.tv/featureControl/getSettings"

TLSFLAG="--tlsv1.2"
if [ "$DEVICE_TYPE" = "broadband" ]; then
    IF_FLAG="--interface $EROUTER_INTERFACE"
else
    IF_FLAG=""
fi
UseCodebig=0
CodebigAvailable=0
RfcRebootCronNeeded=0

#---------------------------------
# Function declarations
#---------------------------------
IsDirectBlocked()
{
    ret=0
    return $ret
}

## Get ECM mac address
getECMMacAddress()
{
    address=`getECMMac`
    mac=`echo $address | tr -d ' ' | tr -d '"'`
    echo $mac
}

estbIp=`getIPAddress`

## FW version from version.txt
getFWVersion()
{
    if [ "$DEVICE_TYPE" = "broadband" ]; then
        # Handle imagename separator being colon or equals
        grep imagename /version.txt | sed 's/.*[:=]//'
    else
        #cat /version.txt | grep ^imagename:PaceX1 | grep -v image
        verStr=`cat /version.txt | grep ^imagename: | cut -d ":" -f 2`
        echo $verStr
    fi
}

## Identifies whether it is a VBN or PROD build
getBuildType()
{
   echo $BUILD_TYPE
}


## Get Controller Id
getControllerId()
{
    echo "2504"
}

## Get ChannelMap Id
getChannelMapId()
{
    echo "2345"
}

## Get VOD Id
getVODId()
{
    echo "15660"
}

###########################################################################
## Get and Set the RFC parameter value                                   ##
###########################################################################
rfcGet () # $1 Name
{
    if [ "$DEVICE_TYPE" = "broadband" ]; then
        dmcli eRT getv $1
    elif [ "$DEVICE_TYPE" = "XHC1" ]; then
        dmcli -g $1
    else
        tr181 $1
    fi
}

rfcSet () # $1 Name $2 Type $3 Value
{
    if [ "$DEVICE_TYPE" = "broadband" ]; then
        dmcli eRT setv $1 $2 $3
    elif [ "$DEVICE_TYPE" = "XHC1" ]; then
        dmcli -s $1="$3"
    else
        tr181 -s -t s -v $3 $1
    fi
}


###########################################################################
## Prerocess the response, so that it could be parsed for features       ##
###########################################################################
preProcessFile()
{
    # Prepare data for variable parsing
        sed -i 's/"name"/\n"name"/g' $FILENAME #
        sed -i 's/{/{\n/g' $FILENAME #
        sed -i 's/}/\n}/g' $FILENAME #
        sed -i 's/"features/\n"features/g' $FILENAME #
        sed -i 's/"/ " /g' $FILENAME #
        sed -i 's/,/ ,\n/g' $FILENAME #
        sed -i 's/:/ : /' $FILENAME #
        sed -i 's/tr181./tr181. /'  $FILENAME #

        sed -i 's/^{//g' $FILENAME # Delete first character from file '{'
        sed -i 's/}$//g' $FILENAME # Delete first character from file '}'
        echo "" >> $FILENAME         # Adding a new line to the file

    if [ "$rfcState" != "INIT" ]; then
        # clear the feature list
        rm -f $RFC_TMP_PATH/rfcFeature.list
    fi
}


###########################################################################
## Report the features                                                   ##
###########################################################################
getFeatures()
{
    if [ -f "$FILENAME" ]; then
        c1=0    #flag to control feature enable definition

        while read line
        do
        #
            feature_Check=`echo "$line" | grep -ci 'name'`

            if [ $feature_Check -ne 0 ]; then
                value2=`echo "$line" | awk '{print $2}'`
                if [ $value2 =  "name" ]; then
                    varName=`echo "$line" | grep name |awk '{print $6}'`
                    c1=1
                fi
            fi

            if [ $c1 -ne 0 ]; then
            # Process enable config line
                enable_Check=`echo "$line" | grep -ci 'enable'`
                if [ $enable_Check -ne 0 ]; then
                    value2=`echo "$line" | awk '{print $2}'`
                    if [ $value2 =  "enable" ]; then
                        value6=`echo "$line" | grep enable |awk '{print $5}'`

                        echo -n " $varName=$value6," >> $RFC_TMP_PATH/rfcFeature.list
                        c1=0
                    fi
                fi
            fi
        done < $FILENAME

        cp $RFC_TMP_PATH/rfcFeature.list $RFC_PATH/rfcFeature.list

        rfcLogging "[Features Enabled]-[STAGING]: `cat $RFC_PATH/rfcFeature.list`"
    else
        rfcLogging "$FILENAME not found."
        return 1
    fi
}

###########################################################################
## Report the features                                                   ##
###########################################################################
featureReport()
{
    preProcessFile
    getFeatures
}

###########################################################################
## Redirect to new Xconf if configured from production Xconf             ##
###########################################################################
getXconfSelect()
{
    if [ -f "$FILENAME" ]; then
        c1=0    #flag to control feature enable definition

        while read line
        do
        #

            value2=`echo "$line" | awk '{print $2}'`
            paramName=`echo "$line" | awk '{print $3}'`
            value6=`echo "$line" | awk '{print $6}'`


            # Extract tr181 data
            enable_Check=`echo "$value2" | grep -ci 'tr181.'`
            if [ $enable_Check -ne 0 ]; then
                configValue=`echo "$line" | awk '{print $7}'`

                enable_Check=`echo "$paramName" | grep -ci 'Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.XconfUrl'`
                if [ $enable_Check -ne 0 ]; then
                    rfcSelectUrl=$configValue
                    URL="$rfcSelectUrl"
                    rfcLogging "NEW Xconf URL configured: $configValue"
                fi

                enable_Check=`echo "$paramName" | grep -ci 'Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.XconfSelector'`
                if [ $enable_Check -ne 0 ]; then
                    rfcSelectOpt=$configValue
                    rfcLogging "NEW Selector name configured $rfcSelectOpt"

                    if [ "$rfcSelectOpt" == "ci" ]; then
                        rfcSelectorSlot="16"
                        rfcState="REDO"
                    elif [ "$rfcSelectOpt" == "automation" ]; then
                        rfcSelectorSlot="19"
                        rfcState="REDO"
                    else
                        rfcSelectorSlot="8"
                        rfcState="CONTINUE"
                    fi

                    rfcLogging "RFC Configured for Slot $rfcSelectorSlot, URL $rfcSelectUrl, State $rfcState "
                fi

            fi

        done < $FILENAME

    else
        rfcLogging "$FILENAME not found."
    fi

    if [ "$rfcState" == "INIT" ]; then
        # Override not configured through Production Xconf, check if there is local override

        rfcLogging "NO NEW XCONF in RFC, finish production Xconf response..."

        # Just continue with production XCONF
        rfcState="CONTINUE"

        rfcSelectorSlot="$RFC_SLOT"
        URL="$RFC_CONFIG_SERVER_URL"
        rfcSelectUrl="$URL"
    fi
}

######################################################################################
## Pre-process the Json response to check if new Xconf server needs to be contacted ##
######################################################################################
preProcessJsonResponse()
{

    if [ "$rfcState" == "INIT" ]; then
        if [ -f "$FILENAME" ]; then
            OUTFILE='/tmp/rfc-current.json'
                        cat /dev/null > $OUTFILE #empty old file
                        cp $FILENAME $OUTFILE

            preProcessFile

            #determine next Xconf target
            getXconfSelect

            # Restore original response
            cp $OUTFILE $FILENAME
                else
            rfcLogging "ERROR: Processing $rfcState (P2) state BUT $FILENAME is missing"
                fi
    elif [ "$rfcState" == "REDO" ]; then
        # This is second passing and NEW request to Xconf is already completed
        rfcState="CONTINUE"
        fi
}
###########################################################################
## Process the response, update the list of variables in rfcVariable.ini ##
###########################################################################
processJsonResponseV()
{
    if [ -f "$FILENAME" ]; then
        OUTFILE='/tmp/rfc-current.json'

                if [ "$rfcState" == "INIT" ]; then
                        cat /dev/null > $OUTFILE #empty old file
                        cp $FILENAME $OUTFILE
                else
                # Extract Whitelists
                        cat $OUTFILE
                        rfcLogging "Utility $RFC_WHITELIST_TOOL is processing $OUTFILE"
                        $RFC_WHITELIST_TOOL $OUTFILE
                        cp $RFC_PATH/$RFC_LIST_FILE_NAME_PREFIX*$RFC_LIST_FILE_NAME_SUFFIX $RFC_RAM_PATH/.

                        rfcLogging "Utility $RFC_WHITELIST_TOOL is COMPLETED"
                        # cat /dev/null > $VARFILE #empty old file
                        rm -f $RFC_TMP_PATH/.RFC_*
                        rm -f $VARFILE
                        rm -f $RFC_PATH/tr181.list   # $PERSISTENT_PATH/RFC/tr181.list

                        # store permanent parameters
                        rfcStashStoreParams

                        # clear RFC data store before storing new values
                        # this is required as sometime key value pairs will simply
                        # disappear from the config data, as mac is mostly removed
                        # to disable a feature rather than having different value
                        echo "RFC: resetting all rfc values in backing store"  >> $RFC_LOG_FILE
                        touch $TR181_STORE_FILENAME
                        $RFC_SET -v true Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.ClearDB >> $RFC_LOG_FILE
                        $RFC_SET -v true Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Bootstrap.Control.ClearDB >> $RFC_LOG_FILE
                        $RFC_SET -v "$(date +%s )" Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.ConfigChangeTime >> $RFC_LOG_FILE

                        # Now retrieve parameters that must persist
                        rfcStashRetrieveParams

                fi

    # prepare json file for parsing
        preProcessFile

    # Process RFC configuration

        c1=0    #flag to control feature enable definition
        c2=0    #flag to control start parameters

        while read line
        do
        # Parse the settings  by feature name
        # 1) Replace the '":' with '='
        # 2) Updating the result in a output file

            feature_Check=`echo "$line" | grep -ci 'name'`
            #echo "--> feature_Check=$feature_Check"
            if [ $feature_Check -ne 0 ]; then
                value2=`echo "$line" | awk '{print $2}'`
                if [ $value2 =  "name" ]; then
                    varName=`echo "$line" | grep name |awk '{print $6}'`
                    #echo "NAME is $varName"
                    rfcVar=$RFC_TMP_PATH"/.RFC_"$varName
                    #echo "VARIABLE $rfcVar is "
                    #echo "$rfcVar=">> $VARFILE
                    c1=1
                    # clear rfc file
                    rm -f $rfcVar.ini
                fi
            fi

            if [ $c1 -ne 0 ]; then
            # Process enable config line
                enable_Check=`echo "$line" | grep -ci 'enable'`
                if [ $enable_Check -ne 0 ]; then
                    value2=`echo "$line" | awk '{print $2}'`
                    if [ $value2 =  "enable" ]; then
                        value6=`echo "$line" | grep enable |awk '{print $5}'`
                        echo "export RFC_ENABLE_$varName=$value6" >> $VARFILE
                        echo "export RFC_ENABLE_$varName=$value6" >> $rfcVar.ini
                        rfcLogging "export RFC_ENABLE_$varName = $value6"
                        echo -n " $varName=$value6," >> $RFC_TMP_PATH/rfcFeature.list
                    fi
                fi

                # Check if feature takes value immediately
                enable_Check=`echo "$line" | grep -ci 'effectiveImmediate'`
                if [ $enable_Check -ne 0 ]; then
                    value6=`echo "$line" | grep effectiveImmediate |awk '{print $5}'`
                    echo "export RFC_$varName"_effectiveImmediate"=$value6" >> $VARFILE
                    echo "export RFC_$varName"_effectiveImmediate"=$value6" >> $rfcVar.ini
                fi

                # Check for configData
                enable_Check=`echo "$line" | grep -ci 'configData'`
                if [ $enable_Check -ne 0 ]; then
                    c2=1
                    continue
                fi

                if [ $c2 -ne 0 ]; then
                # Check for configData end
                    enable_Check=`echo "$line" | grep -ci '}'`
                    if [ $enable_Check -ne 0 ]; then
                    # close the config data section
                        c2=0
                        c1=0
                        echo "" >> $VARFILE  # separate each feature with empty line
                    else
                        enable_Check=`echo "$line" | grep -ci ':'`
                        if [ $enable_Check -ne 0 ]; then
                        # Process configData line

                            value2=`echo "$line" | awk '{print $2}'`
                            paramName=`echo "$line" | awk '{print $3}'`
                            value6=`echo "$line" | awk '{print $6}'`

                            # Extract tr181 data
                            enable_Check=`echo "$value2" | grep -ci 'tr181.'`
                            if [ $enable_Check -eq 0 ]; then
                                # echo "Processing line $line"
                                if [ "$DEVICE_TYPE" != "XHC1" ]; then
                                    echo "export RFC_DATA_$varName"_"$value2=\"$value6\"" >> $VARFILE
                                    echo "export RFC_DATA_$varName"_"$value2=\"$value6\"" >> $rfcVar.ini
                                elif [ "$DEVICE_TYPE" = "XHC1" ]; then
                                    echo "export RFC_DATA_$varName"_"$value2=$value6" >> $VARFILE
                                    echo "export RFC_DATA_$varName"_"$value2=$value6" >> $rfcVar.ini
                                fi
                                rfcLogging "export RFC_DATA_$varName"_"$value2 = $value6"
                            else
                                # echo "Processing line $line"
                                configValue=`echo "$line" | awk '{print $7}'`
                                echo "TR-181: $paramName $configValue"  >> $RFC_PATH/tr181.list
                                if [ "$DEVICE_TYPE" != "XHC1" ]; then
                                paramValue=`$RFC_GET $paramName  2>&1 > /dev/null`
                                elif [ "$DEVICE_TYPE" = "XHC1" ]; then
                                    $RFC_GET $paramName  > /tmp/.paramRFC
                                    paramValue=`cat /tmp/.paramRFC | grep "$paramName" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -d' ' -f3`
                                fi

                                enable_Check=`echo "$paramName" | grep -ci '.X_RDKCENTRAL-COM_RFC.'`
                                if [ $enable_Check -eq 0 ]; then
                                    # This is parameetr outside of RFC namespace and needs to be tested if it is same as already set value
                                    if [ "$paramValue" != "$configValue" ]; then
                                        # new value is different, parameetr must be updated
                                        setConfigValue=1
                                    else
                                        setConfigValue=0
                                    fi
                                else
                                    # Parameters in RFC space must be set again since database is cleared
                                    setConfigValue=1
                                fi

                                if [ $setConfigValue -ne 0 ]; then
                                    if [ "$DEVICE_TYPE" != "XHC1" ]; then
                                    #RFC SET
                                    value8="$RFC_SET -v $configValue  $paramName "
                                    rfcLogging "$value8"
                                    $RFC_SET -v $configValue  $paramName >> $RFC_LOG_FILE
                                    rfcLogging "RFC:  updated for $paramName from value old=$paramValue, to new=$configValue"
                                else
                                        $RFC_SET $paramName=$configValue >> $RFC_LOG_FILE
                                        rfcLogging "RFC:  updated for $paramName from value old=$paramValue, to new=$configValue"
                                    fi
                                else
                                    rfcLogging "RFC: For param $paramName new and old values are same value $configValue"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        done < $FILENAME

        if [ $c1 -ne 0 ];then
            echo "ERROR Mismatch function name enable flag/n"
        fi

        # Lock out future read requests. Existing reads will continue and sourcing of variables
        # will be completed by the time we rename temp copy to reference variable file
        echo 1 > $RFC_WRITE_LOCK

        cp $RFC_TMP_PATH/rfcFeature.list $RFC_PATH/rfcFeature.list
        rfcLogging "[Features Enabled]-[STAGING]: `cat $RFC_PATH/rfcFeature.list`"
        # Now move temporary variable files to operational copies
        mv -f $VARFILE $VARIABLEFILE

        mkdir -p $RFC_PATH
        # Delete all feature files. It is safe to do now since sourcing is faster than processing all variables.
        rm -f $RFC_PATH/.RFC_*
        mv -f $RFC_TMP_PATH/.RFC_* $RFC_PATH/.
        cp  $RFC_RAM_PATH/.*.list  $RFC_PATH

        # Now delete write lock
        rm -f $RFC_WRITE_LOCK

        if [ "$DEVICE_TYPE" != "XHC1" ]; then
        # Close tr-181 parameter update
        echo "RFC: Flush out tr181store.ini file"  >> $RFC_LOG_FILE
        $RFC_SET -v true Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.ClearDBEnd >> $RFC_LOG_FILE
        $RFC_SET -v true Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Bootstrap.Control.ClearDBEnd >> $RFC_LOG_FILE
        # Reload video variables from modified initialization files.
        $RFC_SET -v true "RFC_CONTROL_RELOADCACHE" >> $RFC_LOG_FILE
        fi
        return 0
    else
        rfcLogging "$FILENAME not found."
        return 1
    fi
}
#####################################################################

#####################################################################
rfcGetHashAndTime ()
{
    if [ "$DEVICE_TYPE" = "broadband" ] || [ "$DEVICE_TYPE" = "XHC1" ]; then
    # read from the file since there is no common database on bb
        valueHash=`cat $RFC_RAM_PATH/.hashValue`
        valueTime=`cat $RFC_RAM_PATH/.timeValue`
    else
        valueHash=`$RFC_GET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.ConfigSetHash  2>&1 > /dev/null`
        valueTime=`$RFC_GET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.ConfigSetTime  2>&1 > /dev/null`
    fi
}
#####################################################################
#####################################################################
rfcSetHTValue ()
{
    rfcLogging "RFC: configsethash=$1 at configsettime=$2"

    if [ "$DEVICE_TYPE" = "broadband" ] || [ "$DEVICE_TYPE" = "XHC1" ]; then
        echo "$1" > $RFC_RAM_PATH/.hashValue
        echo "$2" > $RFC_RAM_PATH/.timeValue
    else
        $RFC_SET -v "$1" Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.ConfigSetHash >> $RFC_LOG_FILE
        $RFC_SET -v "$2" Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Control.ConfigSetTime >> $RFC_LOG_FILE
    fi
}


rfcSetHashAndTime ()
{
    # Store and log hash data
    valueHash=`grep configSetHash /tmp/curl_header | awk '{print $2}'`
    valueTime="$(date +%s )"

    rfcSetHTValue $valueHash  $valueTime
}

rfcClearHashAndTime ()
{
    # Store and log hash data
    valueHash="CLEARED"
    valueTime=0

    rfcSetHTValue $valueHash  $valueTime
}

#####################################################################
#  Store and retrieve parameters that should exist
#  regardless if they are provided by Xconf
#####################################################################
rfcStashStoreParams ()
{
    stashAccountId="Unknown"

    if [ "$DEVICE_TYPE" = "broadband" ]; then
        #dmcli GET
        $RFC_GET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.AccountInfo.AccountID  > /tmp/.paramRFC
        stashAccountId=paramValue=`cat /tmp/.paramRFC | grep value: | cut -d':' -f3 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`
    elif [ "$DEVICE_TYPE" = "XHC1" ]; then
        $RFC_GET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.AccountInfo.AccountID  > /tmp/.paramRFC
        stashAccountId=`cat /tmp/.paramRFC | grep "Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.AccountInfo.AccountID" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -d' ' -f3`
    else
        stashAccountId=`$RFC_GET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.AccountInfo.AccountID  2>&1 > /dev/null`
    fi
}

rfcStashRetrieveParams ()
{

    if [ "$DEVICE_TYPE" = "broadband" ]; then
        #dmcli SET

        paramSet=`$RFC_SET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.AccountInfo.AccountID string $stashAccountId | grep succeed| tr -s ' ' `
    elif [ "$DEVICE_TYPE" = "XHC1" ]; then
        $RFC_SET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.AccountInfo.AccountID="$stashAccountId" >> $RFC_LOG_FILE
    else
        $RFC_SET -v "$stashAccountId" Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.AccountInfo.AccountID  >> $RFC_LOG_FILE
    fi

    rfcLogging "RFC: Restored AccountID=$stashAccountId"

}

#####################################################################
#####################################
## Send Http request to the server ##
#####################################
sendHttpRequestToServer()
{
    resp=0
    FILENAME=$1
    URL=$2
    TryWithCodeBig=$3
    EnableOCSPStapling="/tmp/.EnableOCSPStapling"
    EnableOCSP="/tmp/.EnableOCSPCA"

    #Create json string
    if [ "$DEVICE_TYPE" = "broadband" ]; then 
        JSONSTR='estbMacAddress='$(getErouterMacAddress)'&firmwareVersion='$(getFWVersion)'&env='$(getBuildType)'&model='$(getModel)'&ecmMacAddress='$(getMacAddress)'&controllerId='$(getControllerId)'&channelMapId='$(getChannelMapId)'&vodId='$(getVODId)'&partnerId='$(getPartnerId)'&accountId='$(getAccountId)'&version=2'
    elif [ "$DEVICE_TYPE" = "XHC1" ]; then
        JSONSTR='estbMacAddress='$(getEstbMacAddress)'&firmwareVersion='$(getFWVersion)'&env='$(getBuildType)'&model='$(getModel)'&accountHash='$(getAccountHash)'&partnerId='$(getPartnerId)'&accountId='$(getAccountId)'&version=2'
    else
        JSONSTR='estbMacAddress='$(getEstbMacAddress)'&firmwareVersion='$(getFWVersion)'&env='$(getBuildType)'&model='$(getModel)'&ecmMacAddress='$(getECMMacAddress)'&controllerId='$(getControllerId)'&channelMapId='$(getChannelMapId)'&vodId='$(getVODId)'&partnerId='$(getPartnerId)'&accountId='$(getAccountId)'&version=2'
    fi
    #echo JSONSTR: $JSONSTR

    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/lib:/usr/local/lib
    # Generate curl command
    last_char=`echo $URL | awk '$0=$NF' FS=`
    if [ "$last_char" != "?" ]; then
        URL="$URL?"
    fi
    # force https
    URL=`echo $URL | sed "s/http:/https:/g"`
    echo "RFC: Sending request to URL=$URL"

    firmwareVersion=$(getFWVersion)

    if [ -f $RFC_PATH/.version ]; then
        lastFirmware=`cat $RFC_PATH/.version`
        else
        lastFirmware=""
    fi


    if [ $firmwareVersion =  $lastFirmware ]; then
        if [ "$rfcState" == "INIT" ]; then
            paramValue=`rfcGet ${XCONF_SELECTOR_TR181_NAME}  2>&1 > /dev/null`
            if [ "$paramValue" != "prod" ]; then
                valueHash="OVERRIDE_HASH"
                valueTime="0"
            else
                # retrieve hash value for previous data set
                rfcGetHashAndTime
            fi
        else
            rfcGetHashAndTime
        fi
    else
        valueHash="UPGRADE_HASH"
        valueTime="0"
    fi

    if [ $TryWithCodeBig -eq 1 ]; then
        rfcLogging "Attempt to get RFC settings"

        SIGN_CMD="configparamgen $rfcSelectorSlot \"$JSONSTR\""
        eval $SIGN_CMD > /tmp/.signedRequest
        CB_SIGNED_REQUEST=`cat /tmp/.signedRequest`
        rm -f /tmp/.signedRequest
        if [ -f $EnableOCSPStapling ] || [ -f $EnableOCSP ]; then
            CURL_CMD="curl -w '%{http_code}\n'  -D "/tmp/curl_header"  "$IF_FLAG" --cert-status --connect-timeout $timeout -m $timeout "$TLSFLAG" -H "configsethash:$valueHash" -H "configsettime:$valueTime" -o  \"$FILENAME\" \"$CB_SIGNED_REQUEST\""
        else
            CURL_CMD="curl -w '%{http_code}\n'  -D "/tmp/curl_header"  "$IF_FLAG" --connect-timeout $timeout -m $timeout "$TLSFLAG" -H "configsethash:$valueHash" -H "configsettime:$valueTime" -o  \"$FILENAME\" \"$CB_SIGNED_REQUEST\""
        fi
        CURL_CMD_LOG=`echo "$CURL_CMD" | sed -ne 's#oauth_consumer_key=.*oauth_signature.*#-- <hidden> --#p'`
        rfcLogging "CURL_CMD: $CURL_CMD_LOG"
    else
        if [ -f $EnableOCSPStapling ] || [ -f $EnableOCSP ]; then
            CURL_CMD="curl -w '%{http_code}\n'  -D "/tmp/curl_header" "$IF_FLAG" --cert-status --connect-timeout $timeout -m $timeout "$TLSFLAG"  -H "configsethash:$valueHash" -H "configsettime:$valueTime" -o  \"$FILENAME\" '$URL$JSONSTR'"
        else
            CURL_CMD="curl -w '%{http_code}\n'  -D "/tmp/curl_header" "$IF_FLAG" --connect-timeout $timeout -m $timeout "$TLSFLAG"  -H "configsethash:$valueHash" -H "configsettime:$valueTime" -o  \"$FILENAME\" '$URL$JSONSTR'"
        fi
        rfcLogging "CURL_CMD: $CURL_CMD"
    fi

    # Execute curl command
    result= eval $CURL_CMD > $HTTP_CODE
    TLSRet=$?
    case $TLSRet in
        35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
            rfcLogging "RFC: HTTPS $TLSFLAG failed to connect to $1 server with curl error code $TLSRet"
            ;;
    esac

    #echo "Processing $FILENAME"
    sleep 2 # $timeout

    # Get the http_code
    http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
    retSs=$?
    rfcLogging "TLSRet = $TLSRet http_code: $http_code"


    if [ $TLSRet = 0 ] && [ "$http_code" = "404" ]; then
        rfcLogging "Received HTTP 404 Response from Xconf Server. Retry logic not needed"
    # Remove previous configuration
        rm -f $RFC_PATH/.RFC_*
        rm -rf $RFC_TMP_PATH
        rm -f $VARIABLEFILE
        rfcLogging "[Features Enabled]-[NONE]: "

    # Now delete write lock, if set
        rm -f $RFC_WRITE_LOCK
        resp=0
        echo 0 > $RFCFLAG
    elif [ "$http_code" = "304" ]; then
        # Data did not change, no new data delivered, and no further processing
        rfcLogging "HTTP request success. Response unchanged (304). No processing"
        if [ "$DEVICE_TYPE" != "broadband" ]; then
            # Restore whitelists if available
            cp $RFC_PATH/$RFC_LIST_FILE_NAME_PREFIX*$RFC_LIST_FILE_NAME_SUFFIX $RFC_RAM_PATH/.
        fi
        resp=0
        echo 1 > $RFCFLAG
        rfcLogging "[Features Enabled]-[ACTIVE]: `cat $RFC_PATH/rfcFeature.list`"

    elif [ $retSs -ne 0 -o "$http_code" != "200" ] ; then   # check for retSs is probably superfluous
        rfcLogging "HTTP request failed"
        resp=1
    else
        rfcLogging "HTTP request success. Processing response.."

                # Pre-process Json Response to check if new Xconf server needs to be contacted
                preProcessJsonResponse

        stat=$?
        rfcLogging "preProcessJsonResponse returned $stat"
         if [ "$rfcState" == "REDO" ]; then
            rfcLogging " RFC requires new Xconf request to server $rfcSelectUrl"
            rfcLogging "RFC requires new Xconf request to server $rfcSelectUrl!!"
            resp=1

            return $resp
        else
            rfcLogging "Continue processing RFC response rfcState=$rfcState"
        fi


                # Process the JSON response
        if [ "$DEVICE_TYPE" = "broadband" ]; then
            processJsonResponseB
            featureReport
        else
            processJsonResponseV
        fi
        stat=$?
        rfcLogging "Process JSON Response returned $stat"
        if [ "$stat" != 0 ]; then
            rfcLogging "Processing Response Failed!!"
            resp=1
        else
            resp=0
            echo 1 > $RFCFLAG
        fi
        rfcLogging "COMPLETED RFC PASS"

        # Now store configuration so that it could be used by other processes

        XconfEndpoint="$rfcSelectOpt"
        rfcLogging "STORRING XCONF URL AND SLOT NAME"
        rfcSet ${XCONF_SELECTOR_TR181_NAME} string "$rfcSelectOpt" >> $RFC_LOG_FILE
        rfcSet ${XCONF_URL_TR181_NAME} string "$rfcSelectUrl" >> $RFC_LOG_FILE    

    fi
    rfcLogging "resp = $resp"

    if [ $resp = 0 ]; then
        rfcSetHashAndTime

        echo $firmwareVersion > $RFC_PATH/.version

        ## copy all RFC files to old non-secure location for backward compatibility with previous release
        ##
        if [ "$http_code" = "200" ]; then
            rfcLogging "Updating RFC files to old location"
            rm -r $OLD_RFC_BASE/RFC
            cp -r $RFC_BASE/RFC $OLD_RFC_BASE
        fi
        ##
        ## The block above to be removed after 2 releases (Q2/2019)

        # Execute postprocessing
        if [ -f "$RFC_POSTPROCESS" ]; then
            rfcLogging "Starting Post Processing"
            $RFC_POSTPROCESS &
        else
            rfcLogging "No $RFC_POSTPROCESS script"
        fi
    else
        rfcClearHashAndTime
    fi

    return $resp
}
#####################################################################

#####################################################################
rfcLogging ()
{
    if [ "$DEVICE_TYPE" = "broadband" ]; then
        echo_t "[RFC]:: $1" >> $RFC_LOG_FILE
    else
        echo "`/bin/timestamp` [RFC]:: $1" >> $RFC_LOG_FILE
    fi
}
#####################################################################

#####################################################################
waitForIpAcquisition()
{
    loop=1
    counter=0
    while [ $loop -eq 1 ]
    do
        estbIp=`getIPAddress`
        if [ "X$estbIp" == "X" ]; then
            sleep 10
        else
            if [ "$IPV6_ENABLED" = "true" ]; then
                if [ "Y$estbIp" != "Y$DEFAULT_IP" ] && [ -f $WAREHOUSE_ENV ]; then
                    loop=0
                elif [ ! -f /tmp/estb_ipv4 ] && [ ! -f /tmp/estb_ipv6 ]; then
                    sleep 10
                    rfcLogging "waiting for IPv6 IP"
                    let counter++
                elif [ "Y$estbIp" == "Y$DEFAULT_IP" ] && [ -f /tmp/estb_ipv4 ]; then
                    rfcLogging "waiting for IPv6 IP"
                    let counter++
                    sleep 10
                else
                    loop=0
                fi
            else
                if [ "Y$estbIp" == "Y$DEFAULT_IP" ]; then
                    rfcLogging "waiting for IPv4 IP"
                    sleep 10
                    let counter++
                else
                    loop=0
                fi
            fi
        fi
    done
}
#####################################################################

#####################################################################
CallXconf()
{

    UseCodebig=0
    CodebigAvailable=0
    # XB3 platforms doesn't have os-release flag
    if [ -f /etc/os-release ] || [ "$DEVICE_TYPE" = "broadband" ]; then
        if [ -f /usr/bin/configparamgen ]; then
            if [ "$DEVICE_TYPE" = "broadband" ]; then
                CodeBigFirst=`$RFC_GET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodeBigFirst.Enable | grep value | cut -f3 -d : | cut -f2 -d " "`
            else
                CodeBigFirst=`$RFC_GET -g Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodeBigFirst.Enable 2>&1 > /dev/null`
            fi
            CodebigAvailable=1
            if [ "$CodeBigFirst" = "true" ]; then
                rfcLogging "RFC: CodebigFirst is enabled"
                UseCodebig=1
            else
                rfcLogging "RFC: CodebigFirst is disabled"
                IsDirectBlocked
                UseCodebig=$?
            fi
        else
            rfcLogging "RFC: CodebigFirst support is not available"
        fi
    fi

    loop=1
    while [ $loop -eq 1 ]
    do
        if [ ! $estbIp ] ;then
            #echo "waiting for IP ..."
            rfcLogging "Waiting for IP"
            sleep 15
        else
            retSx=1
            if [ "$DEVICE_TYPE" != "mediaclient" ] && [ "$estbIp" == "$default_IP" ] ; then
                retSx=0
            fi
            count=0
            while [ $retSx -ne 0 ]
            do
                sleep 1
                loop=0
                rfcLogging "Box IP is $estbIp"

                sendHttpRequestToServer $FILENAME $URL $UseCodebig
                retSx=$?
                rfcLogging "sendHttpRequestToServer returned $retSx"
                if [ "$rfcState" == "REDO" ]; then
                    # We have to abandon this data and start new request to redirect to new Xconf
                    rm -f $RFC_WRITE_LOCK
                    return 2
                fi

                #If sendHttpRequestToServer method fails
                if [ $retSx -ne 0 ]; then
                    rfcLogging "Processing Response Failed!!"
                    count=$((count + 1))
                    if [ $count -eq $RETRY_COUNT ]; then
                        if [ "$DEVICE_TYPE" !=  "XHC1" ];then
                            if [ $CodebigAvailable -eq 1 ]; then
                                if [ $UseCodebig -eq 1 ]; then
                                    IsDirectBlocked
                                    skipdirect=$?           # check to see if direct communication is allowed
                                    if [ $skipdirect -eq 0 ]; then  # if direct is allowed
                                        UseCodebig=0                # fallback to direct
                                    else
                                        count=$((count + 1))    # force exit below, no need to continue
                                    fi
                                else
                                    UseCodebig=1                # we were direct, try Codebig fallback
                                fi
                            else
                                count=$((count + 1))    # force exit below
                            fi
                        else #XHC1 - Codebig tries
                            #reset counter and retry count for codebig tries
                            if [ $UseCodebig -eq 0 ]; then
                                UseCodebig=1
                                count=0
                                RETRY_COUNT=2
                            fi
                        fi
                    fi

                    if [ $count -gt $RETRY_COUNT ]; then
                        rfcLogging "$RETRY_COUNT tries failed. Giving up..."
                        rm -rf $FILENAME $HTTP_CODE
                        rfcLogging "Exiting script."
                        echo 0 > $RFCFLAG
                        #   exit 0
                        return 0
                    fi
                    rfcLogging "count = $count. Sleeping $RETRY_DELAY seconds ..."
                    rm -rf $FILENAME $HTTP_CODE
                    sleep $RETRY_DELAY
                else
                    rm -rf $HTTP_CODE
                fi
            done
            sleep 15
        fi
    done
# Save cron info
        if [ "$rfcState" != "INIT" ]; then
        if [ -f /tmp/DCMSettings.conf ]
        then
            cat /tmp/DCMSettings.conf | grep 'urn:settings:CheckSchedule:cron' > $PERSISTENT_PATH/tmpDCMSettings.conf
        fi
        fi

# Delete write lock if somehow we did not do it until now
    rm -f $RFC_WRITE_LOCK
#everything is OK
    return 1
}

###############################################
##GET parameter datatype using dmcli and do SET
##    This broadband specific code
###############################################
parseConfigValue()
{
    configKey=$1
    configValue=$2
    RebootValue=$3
    #Remove tr181
    paramName=`echo $configKey | grep tr181 | tr -s ' ' | cut -d "." -f2- `

    #Do dmcli for paramName preceded with tr181
    if [ -n "$paramName" ]; then
        rfcLogging "Parameter name $paramName"
        rfcLogging "Parameter value  $configValue"
        #dmcli GET
        $RFC_GET $paramName  > /tmp/.paramRFC

        paramType=`cat /tmp/.paramRFC | grep type| tr -s ' ' |cut -f3 -d" " | tr , " "`
        if [ -n "$paramType" ]; then
            rfcLogging "paramType is $paramType"
            #dmcli get value
            paramValue=`cat /tmp/.paramRFC | grep value: | cut -d':' -f3 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`
                        rfcLogging "RFC: old parameter value $paramValue "
            if [ "$paramValue" != "$configValue" ]; then
                        #dmcli SET
                        paramSet=`$RFC_SET $paramName $paramType "$configValue" | grep succeed| tr -s ' ' `
                        if [ -n "$paramSet" ]; then
                            rfcLogging "RFC:  updated for $paramName from value old=$paramValue, to new=$configValue"
                                if [ $RebootValue -eq 1 ]; then
                                        if [ -n "$RfcRebootCronNeeded" ]; then
                                                RfcRebootCronNeeded=1;
                                                 rfcLogging "RFC: Enabling RfcRebootCronNeeded since $paramName old value=$paramValue, new value=$configValue, RebootValue=$RebootValue"
                                        fi

                                fi
                        else
                            rfcLogging "RFC: dmcli SET failed for $paramName with value $configValue"
                        fi
                    else
                rfcLogging "RFC: For param $paramName new and old values are same value $configValue"
                    fi
        else
            rfcLogging "dmcli GET failed for $paramName "
        fi
    fi
}

processJsonResponseB()
{
    rfcLogging "Curl success"
    if [ -e /usr/bin/dcmjsonparser ]; then
        rfcLogging "dcmjsonparser binary present"
        /usr/bin/dcmjsonparser $FILENAME  >> $RFC_LOG_FILE

        if [ -f $DCM_PARSER_RESPONSE ]; then
            rfcLogging "$DCM_PARSER_RESPONSE file is present"
            file=$DCM_PARSER_RESPONSE
            $RFC_SET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodebigSupport bool false
            $RFC_SET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.ContainerSupport bool false
            RfcRebootCronNeeded=0;
            # here #~ is a delimiter to cut key, value and ImediateReboot values
            while read line; do
                key=`echo $line| awk -F '#~' '{print $1}'`
                value=`echo $line|awk -F '#~' '{print $2}'`
                ImediateReboot=`echo $line|awk -F '#~' '{print $3}'`
                rfcLogging "key=$key value=$value ImediateReboot=$ImediateReboot"
                parseConfigValue $key "$value" $ImediateReboot
            done < $file
        else
            rfcLogging "$DCM_PARSER_RESPONSE is not present"
        fi

        if [ -f "$RFC_POSTPROCESS" ]
        then
            rfcLogging "Calling RFCpostprocessing"
            $RFC_POSTPROCESS &
        else
            rfcLogging "ERROR: No $RFC_POSTPROCESS script"
        fi

    else
        rfcLogging "binary dcmjsonparse is not present"
    fi
}
##############################################################################
#---------------------------------
#        Main App
#---------------------------------
##############################################################################

# Check if RFC script is already locked. If yes, RFC processing is in progress, just exit from the shell
if [ -f $RFC_SERVICE_LOCK ]; then
    rfcLogging "RFC: Service in progress. New instance not allowed. Lock file $RFC_SERVICE_LOCK is locked!"
    exit 1
fi

# Now Lock the recursion for this script, to prevent multiple concurent RFC read requests
echo 1 > $RFC_SERVICE_LOCK
rfcLogging "RFC: Starting service, creating lock "

waitForIpAcquisition

rfcLogging "Starting execution of RFCbase.sh"


if [ -f $RDK_PATH/RFCpreprocess.sh ]; then
    rfcLogging "Starting Pre Processing"
    sh $RDK_PATH/RFCpreprocess.sh &
fi

if [ "$DEVICE_TYPE" != "broadband" ]; then
    if [ "$DEVICE_TYPE" = "XHC1" ]; then
        rfcLogging "Waiting 5 minutes before attempting to query xconf"
        sleep  300
    else
        rfcLogging "Waiting 2 minutes before attempting to query xconf"
        sleep 120
    fi
fi

# Initialize RFC configuration state

rfcSelectUrl="$RFC_CONFIG_SERVER_URL"
rfcSelectorSlot="$RFC_SLOT" # values are "8" for "prod", "16" for "ci", "19" for "automation"
URL="$RFC_CONFIG_SERVER_URL"
rfcSelectUrl="$URL"

if [ "$rfcState" == "LOCAL" ]; then
    rfcLogging "CALLING Direct override from local rfc.properties, state $rfcState"
    rfcState="REDO"
    rfcSelectOpt="local"
else
    rfcLogging "CALLING Initally PROD XConf FOR RFC CONFIGURATION, state $rfcState"
    rfcLogging "    URL: $URL"
    rfcSelectOpt="prod"

    CallXconf
        retSs=$?
        rfcLogging "First call Returned $retSs"
fi
#Check the Xconf url to be used based on Xconf selector.

if [ "$rfcState" == "REDO" ]; then
    rfcLogging "Calling request to NEW XConf..."
    rfcLogging "    URL: $URL"

    CallXconf
fi


# Finish the IP Firewall Configuration
if [ -f $RDK_PATH/iptables_init ]; then
    sh $RDK_PATH/iptables_init Finish &
    rfcLogging "Finish the IP Firewall Configuration"
fi

rfcLogging "START CONFIGURING RFC CRON"
#cat $current_cron_file >> $RFC_LOG_FILE

cron=''
if [ -f /tmp/DCMSettings.conf ]
then
        cat /tmp/DCMSettings.conf | grep 'urn:settings:CheckSchedule:cron' > $PERSISTENT_PATH/tmpDCMSettings.conf
        cron=`cat /tmp/DCMSettings.conf | grep 'urn:settings:CheckSchedule:cron' | cut -d '=' -f2`
else
        if [ -f $PERSISTENT_PATH/tmpDCMSettings.conf ]
        then
              cron=`cat $PERSISTENT_PATH/tmpDCMSettings.conf | grep 'urn:settings:CheckSchedule:cron' | cut -d '=' -f2`
        fi

fi

# Now delete service lock
rfcLogging "RFC: Completed service, deleting lock "
rm -f $RFC_SERVICE_LOCK


if [ -n "$cron" ]
then
        cron_update=1

        vc1=`echo "$cron" | awk '{print $1}'`
        vc2=`echo "$cron" | awk '{print $2}'`
        vc3=`echo "$cron" | awk '{print $3}'`
        vc4=`echo "$cron" | awk '{print $4}'`
        vc5=`echo "$cron" | awk '{print $5}'`
        if [ $vc1 -gt 2 ]
        then
                vc1=`expr $vc1 - 3`
        else
                vc1=`expr $vc1 + 57`
                if  [ $vc2 -eq 0 ]
                then
                        vc2=23
                else
                        vc2=`expr $vc2 - 1`
                fi
        fi

        cron=''
        cron=`echo "$vc1 $vc2 $vc3 $vc4 $vc5"`

        echo "Configuring cron job for RFCbase.sh" >> $RFC_LOG_FILE
        crontab -l -c /var/spool/cron/ > $current_cron_file
        sed -i '/[A-Za-z0-9]*RFCbase.sh[A-Za-z0-9]*/d' $current_cron_file
        if [ "$DEVICE_TYPE" != "XHC1" ]; then
            echo "$cron /bin/sh $RDK_PATH/RFCbase.sh >> $RFC_LOG_FILE 2>&1" >> $current_cron_file
        else
            echo "$cron /bin/sh $RDK_PATH/RFCbase.sh" >> $current_cron_file
        fi

        if [ $cron_update -eq 1 ];then
                crontab $current_cron_file -c /var/spool/cron/
        fi

    # Log cron configuration
    if [ "$DEVICE_TYPE" != "broadband" ]; then
        echo "/var/spool/cron/root:" >> $RFC_LOG_FILE
    else
        echo "/var/spool/cron/crontabs/root:" >> $RFC_LOG_FILE
    fi
        cat $current_cron_file >> $RFC_LOG_FILE

else
    if [ "$DEVICE_TYPE" != "broadband" ]; then
        # No valid cron configuration was found, just set Xconf for retry in next 5 hours
        rfcLogging "RFC: NO cron data found, retry in 5 hours RFC CONFIGURATION"
        sleep 18000

        rfcState="CONTINUE"
        CallXconf
        retSs=$?
        rfcLogging "Second call Returned $retSs"
    fi
fi

     if [ "$RfcRebootCronNeeded" = "1" ] && [ "$DEVICE_TYPE" = "broadband" ]; then
            #Effectictive Reboot is required for the New RFC config. calling the script which will schedule cron to reboot in maintence w
            rfcLogging "RFC: RfcRebootCronNeeded=$RfcRebootCronNeeded. calling script to schedule reboot in maintence window "
            sh /etc/RfcRebootCronschedule.sh &
     fi

