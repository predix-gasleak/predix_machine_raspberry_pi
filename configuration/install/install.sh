#!/bin/bash
# Copyright (c) 2012-2016 General Electric Company. All rights reserved.
# The copyright to the computer software herein is the property of
# General Electric Company. The software may be used and/or copied only
# with the written permission of General Electric Company or in accordance
# with the terms and conditions stipulated in the agreement/contract
# under which the software has been supplied.

# This install script will be called by yeti which will provide three arguements
# The first argument is the Predix Home directory which is the directory to the 
# Predix Machine container
# The second arguement is the path to the configuration directory.  This contains 
# the new configuration application to be installed.
# The third arguement is the name of the zip.  This must be used to create
# the JSON file to verify the status of the installation.  The JSON must be
# placed in the appdata/airsync directory with the name $ZIPNAME.json

# Files can be added to the whitelist so they are not overwritten.  These could 
# include configurations that contain encoded passwords or parameters generated
# by the container on startup.

# Updating the configuration proceeds as follows:
# 1. Make a backup of previous configuration
# 2. Overlay configuration files found in the directory if they are not in the whitelist
# 3. Return an error code or 0 for success

status="failure"
errorcode="1"
message="Installation failed unexpectedly."

writeConsoleLog () {
	echo "$(date +"%m/%d/%y %H:%M:%S") $1"
	echo "$(date +"%m/%d/%y %H:%M:%S") $1" >> "$LOG"
}

killmbsa () {
	sh "$PREDIXHOME/mbsa/bin/mbsa_stop.sh" >> "$LOG" 2>&1 || code=$?
	if [ -z "$code" ] || [ $code -eq 0 ]; then
		# code is an empty string unless mbsa throws an error. Empty string is equivalent to exit code 0
		writeConsoleLog "MBSA stopped, container shutting down..."
	elif [ $code -eq 2 ]; then
		# 2 is the exit code mBSA sends when attempting to stop an already stopped container
		writeConsoleLog "MBSA is shut down, no container was running."
	else
		writeConsoleLog "MBSA failed to shut down the container. Attempting to forcibly close..."
	fi
	mbsapid=$(ps ax | grep mbsae.core | grep -v grep | awk '{ print $1 }')
	for mbsaprcs in $mbsapid; do
		kill -9 $mbsaprcs
		echo -n "Killed mbsa (process $mbsaprcs)"
	done
}

finish () {
	writeConsoleLog "$message"
	if [ $errorcode -eq 0 ]; then
		printf "{\n\t\"status\" : \"$status\",\n\t\"message\" : \"$message\"\n}\n" > "$AIRSYNC/$ZIPNAME.json"
	else
		printf "{\n\t\"status\" : \"$status\",\n\t\"errorcode\" : $errorcode,\n\t\"message\" : \"$message\"\n}\n" > "$AIRSYNC/$ZIPNAME.json"
	fi
	# Start the container before exiting
	nohup sh "$PREDIXHOME/mbsa/bin/mbsa_start.sh" > /dev/null 2>&1 &
}
trap finish EXIT

PREDIXHOME=$1
CONFIG=$2
ZIPNAME=$3
DATE=`date +%m%d%y%H%M%S`
LOG=$PREDIXHOME/logs/installations/install_configuration${DATE}.txt
AIRSYNC=$PREDIXHOME/appdata/airsync

# These configurations should not be overwritten
#   com.ge.dspmicro.predixcloud.identity.config (client id and secret)
#   com.proximetry.osgiagent.impl.DevicesService.cfg (proximetry device id)
#   com.ge.dspmicro.storeforward-*.config  (generated database password will never accessible again if you overwrite)
#   com.ge.dspmicro.device.techconsole.config – This says if the technician console should be enabled. This should only be done through the the command and not through configuration overwrite.
WHITELIST=( com.ge.dspmicro.predixcloud.identity.config \
            com.proximetry.osgiagent.impl.DevicesService.cfg \
            com.ge.dspmicro.device.techconsole.config \
            org.apache.http.proxyconfigurator-0.config \
            com.ge.dspmicro.storeforward-0.config \
            com.ge.dspmicro.storeforward-1.config \
            com.ge.dspmicro.storeforward-2.config \
            com.ge.dspmicro.storeforward-3.config )

# Shutdown container for update
echo "$(date +"%m/%d/%y %H:%M:%S") ##########################################################################">> "$LOG"
echo "$(date +"%m/%d/%y %H:%M:%S") #                 Shutting down container for update                     #">> "$LOG"
echo "$(date +"%m/%d/%y %H:%M:%S") ##########################################################################">> "$LOG"
killmbsa
while ps aux | grep mbsae.core | grep -v grep > /dev/null; do
	 writeConsoleLog "Error exiting mBSA processes, will try again in 1 minute"
	sleep 60
done

writeConsoleLog "Updating the configuration directory."
writeConsoleLog "Looking for whitelisted files in the installation package."
for config in "${WHITELIST[@]}"; do
	configpath="$(find $CONFIG -name "${config}")"
	relpath=${configpath:${#CONFIG}}
	if [ -e "$PREDIXHOME${relpath}" ]; then
		writeConsoleLog "Removing whitelisted file ${configpath}"
		rm "${configpath}" >> "$LOG" 2>&1
	fi
done

# Update the configuration by removing any old backups, renaming the
# current installed to configuration.old, and adding the updated configuration

if [ -d "$PREDIXHOME/configuration" ]; then
	writeConsoleLog "Updating configuration. Backup of current stored in configuration.old"
	if [ -d "$PREDIXHOME/configuration.old" ]; then
		writeConsoleLog "Updating configuration.old backup to revision before this update"
		rm -r "$PREDIXHOME/configuration.old/">>"$LOG" 2>&1
		if [ $? -eq 0 ]; then
			writeConsoleLog "Previous configuration.old removed"
		else
			message="Previous configuration.old could not be removed."
			errorcode="1"
			status="failure"
			exit 1
		fi
	fi
	cp -Rp "$PREDIXHOME/configuration/" "$PREDIXHOME/configuration.old/">>"$LOG" 2>&1
	if [ $? -eq 0 ]; then
		writeConsoleLog "Configuration backup created as configuration.old"
	else
		message="Previous configuration directory could not be copied to configuration.old."
		errorcode="2"
		status="failure"
		exit 2
	fi
fi
cp -Rp "$CONFIG/configuration"/* "$PREDIXHOME/configuration">>"$LOG" 2>&1
if [ $? -eq 0 ]; then
	message="Configuration updated"
	errorcode="0"
	status="success"
	exit 0
else
	message="Configuration could not be updated."
	errorcode="3"
	status="failure"
	exit 3
fi