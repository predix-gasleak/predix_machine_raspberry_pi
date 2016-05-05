#!/bin/bash
# Copyright (c) 2012-2016 General Electric Company. All rights reserved.
# The copyright to the computer software herein is the property of
# General Electric Company. The software may be used and/or copied only
# with the written permission of General Electric Company or in accordance
# with the terms and conditions stipulated in the agreement/contract
# under which the software has been supplied.

writeConsoleLog () {
	echo "$(date +"%m/%d/%y %H:%M:%S") $1"
	echo "$(date +"%m/%d/%y %H:%M:%S") $1" >> "$LOG"
}

PREDIXHOME=$(dirname "$0")/..
RUNDATE=`date +%m%d%y%H%M%S`
LOG=$PREDIXHOME/logs/installations/yeti_stop_log${RUNDATE}.txt
writeConsoleLog "SHUTTING DOWN..."
touch "$PREDIXHOME/yeti/.bumble"
if [ "$?" != "0" ] && [ "$?" != "" ]; then
	writeConsoleLog "Error shutting down yeti, access to create shutdown signal in yeti directory is denied."
	exit 1
fi
let SHUTDOWNCHECKCNT=1
while true; do
	mbsapid=$(ps ax | grep mbsae.core | grep -v grep | awk '{ print $1 }')
	if [ "$SHUTDOWNCHECKCNT" -ge 180 ]; then
		writeConsoleLog "Shutdown took longer than 3 minutes.  Check the logs in logs/installations for more information."
		exit 1
	elif [ "$mbsapid" != "" ]; then
		writeConsoleLog "Checking for shutdown completion. Check number $SHUTDOWNCHECKCNT"
		sleep 1
		let SHUTDOWNCHECKCNT=SHUTDOWNCHECKCNT+1
	else
		writeConsoleLog "Complete. Yeti has shutdown."
		exit 0
	fi
done