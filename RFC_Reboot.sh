#! /bin/sh

source /usr/ccsp/tad/corrective_action.sh

LOG_FILE="/rdklogs/logs/dcmrfc.log"

#Setting last reboot to rfc_reboot
echo_t "[RFC_Reboot.sh] setting last reboot to rfc_reboot" >> $LOG_FILE
setRebootreason rfc_reboot 1

#take log back up and reboot

echo_t "[RFC_Reboot.sh] take log back up and reboot" >> $LOG_FILE
sh /rdklogger/backupLogs.sh &
