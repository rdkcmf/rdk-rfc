#!/bin/busybox sh
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
## Script to execute after RFC response is processed
## Author:
##################################################################
. /etc/include.properties
. /etc/device.properties

if [ -z $LOG_PATH ]; then
    if [ "$DEVICE_TYPE" = "broadband" ]; then
        LOG_PATH="/rdklogs/logs"
    else
        LOG_PATH="/opt/logs"
    fi
fi

if [ -z $RDK_PATH ]; then
    RDK_PATH="/lib/rdk"
fi

echo "[RFC]:: POSTPROCESSING IS RUN NOW !!!" >> $LOG_PATH/rfcscript.log

if [ "$DEVICE_TYPE" = "broadband" ]; then
# PROCESSING BROADBAND SPECIFIC CALLS

    #Check for lock file to prevent multiple instances of rfc_refresh.sh
    if [ ! -f /tmp/.rfcLock ] ; then
       ls /tmp/RFC/.RFC_* | grep -i sshwhitelist > /dev/null
       sshFileCheck=$?
       if [ $sshFileCheck -eq 0 ] ; then
          RFC_SSH_FILE="$(ls /tmp/RFC/.RFC_* | grep -i sshwhitelist)"
          if [ -s $RFC_SSH_FILE ] ; then
             echo "RFC File for SSH present. Refreshing Firewall" >> $LOG_PATH/dcmrfc.log
             #sh $RDK_PATH/rfc_refresh.sh SSH_REFRESH &
	     sysevent set firewall-restart
          else
             echo "RFC File for SSH is not present or empty" >> $LOG_PATH/dcmrfc.log
          fi
       fi
       dmcli eRT setv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.Snmpv3DHKickstart.RFCUpdateDone bool true
       echo "[RFC]:: RFCUpdateDone set to true" >> $LOG_PATH/rfcscript.log
    else
       echo "/tmp/.rfcLock file present" >> $LOG_PATH/dcmrfc.log
    fi
else
# PROCESSING VIDEO SPECIFIC CALLS
    if [ "$DEVICE_TYPE" != "XHC1" ]; then
        # Insert the Dynamic White List Servers
        if [ -f $RDK_PATH/iptables_init ]; then
            /bin/busybox sh $RDK_PATH/iptables_init SSH_Refresh &
            /bin/busybox sh $RDK_PATH/iptables_init SNMP_Refresh &
        fi
    fi
fi

if [ -f $RDK_PATH/tch_sshwhitlist.sh ]; then
    sh $RDK_PATH/tch_sshwhitlist.sh &
fi

echo "[RFC]:: POSTPROCESSING IS COMPLETE !!!" >> $LOG_PATH/rfcscript.log
