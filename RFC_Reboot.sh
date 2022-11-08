#! /bin/sh
##########################################################################
# If not stated otherwise in this file or this component's LICENSE
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


if [ -f /etc/device.properties ] ; then
        . /etc/device.properties
fi

if [ "$DEVICE_TYPE" = "XHC1" ]; then
        if [ -f /lib/rdk/utils.sh ]; then
                . /lib/rdk/utils.sh
        fi

        if [ -z $LOG_PATH ]; then
                LOG_PATH="/opt/logs"
        fi

        RFC_LOG_FILE="$LOG_PATH/rfcscript.log"

        # Ensure deviceInitiatedFWDnld is not running before reboot is triggered
        FWDnd_pid=`ps -ef | grep deviceInitiatedFWDnld.sh |grep -v grep | awk '{print $1}'`
        if [ ! "$FWDnd_pid" ] ; then
                # Update reboot reason
                echo "`/bin/timestamp` [RFC]:: setting last reboot to rfc_reboot" >> $RFC_LOG_FILE
                echo `getISO8601time` "RebootReason: rfc_reboot" > $LOG_PATH/rebootInfo.log
                echo "RebootReason: rfc_reboot" > $PARODUS_FILE_PATH
                dmcli -s Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason="rfc_reboot"

                pidParodus=$(pidof parodus)
                if [ ! -z "$pidParodus" ];then
                        echo `/bin/timestamp` "Stopping Parodus"
                        kill -15 $pidParodus
                fi
                sleep 1
                /usr/local/bin/reboot 3 &
        fi

elif [ "$DEVICE_TYPE" = "broadband" ]; then
        source /usr/ccsp/tad/corrective_action.sh

        LOG_FILE="/rdklogs/logs/dcmrfc.log"

        #Setting last reboot to rfc_reboot
        echo_t "[RFC_Reboot.sh] setting last reboot to rfc_reboot" >> $LOG_FILE
        setRebootreason rfc_reboot 1

	isWanLinkHealEnabled=`syscfg get wanlinkheal`
	if [ "x$isWanLinkHealEnabled" == "xtrue" ];then
	    /usr/ccsp/tad/check_gw_health.sh store-health
	fi

        #take log back up and reboot

        echo_t "[RFC_Reboot.sh] take log back up and reboot" >> $LOG_FILE
        sh /rdklogger/backupLogs.sh &
fi

