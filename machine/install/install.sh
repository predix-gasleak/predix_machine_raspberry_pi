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
# The second arguement is the path to the machine directory.  This contains 
# the new machine application to be installed.
# The third arguement is the name of the zip.  This must be used to create
# the JSON file to verify the status of the installation.  The JSON must be
# placed in the appdata/airsync directory with the name $ZIPNAME.json

# Updating the machine application proceeds as follows:
# 1. Make a backup of previous machine application
# 2. Add new machine application
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

prosystkey () {
	# Prosyst has a limited key that must not be replaced by the installation
	writeConsoleLog "Backing up Prosyst limited key."
	cp -Rp "$PREDIXHOME/machine/bin/vms/domain.crp" "$MACHINE/machine/bin/vms/domain.crp">>"$LOG" 2>&1
	if [ ! $? -eq 0 ]; then
		message="Prosyst limited key could not be inserted into the update package."
		errorcode="4"
		status="failure"
		exit 1
	fi
}

PREDIXHOME=$1
MACHINE=$2
ZIPNAME=$3
DATE=`date +%m%d%y%H%M%S`
LOG=$PREDIXHOME/logs/installations/install_machine${DATE}.txt
AIRSYNC=$PREDIXHOME/appdata/airsync
# Update the machine application by removing any old backups, renaming the
# current installed application to machine.old, and adding the updated machine
# application

# Shutdown container for update
echo "$(date +"%m/%d/%y %H:%M:%S") ##########################################################################">> "$LOG"
echo "$(date +"%m/%d/%y %H:%M:%S") #                 Shutting down container for update                     #">> "$LOG"
echo "$(date +"%m/%d/%y %H:%M:%S") ##########################################################################">> "$LOG"
killmbsa
while ps aux | grep mbsae.core | grep -v grep > /dev/null; do
	writeConsoleLog "Error exiting mBSA processes, will try again in 1 minute"
	sleep 60
done

prosystkey
writeConsoleLog "Updating the machine directory."
if [ -d "$PREDIXHOME/machine" ]; then
	writeConsoleLog "Updating machine application. Backup of current application stored in machine.old."
	if [ -d "$PREDIXHOME/machine.old" ]; then
		writeConsoleLog "Updating machine.old application backup to revision before this update."
		rm -r "$PREDIXHOME/machine.old/">>"$LOG" 2>&1
		if [ $? -eq 0 ]; then
			writeConsoleLog "Previous machine.old removed."
		else
			message="Previous machine.old could not be removed."
			errorcode="1"
			status="failure"
			exit 1
		fi
	fi
	mv "$PREDIXHOME/machine/" "$PREDIXHOME/machine.old/">>"$LOG" 2>&1
	if [ $? -eq 0 ]; then
		writeConsoleLog "The machine application backup created as machine.old."
	else
		message="The machine application could not be renamed to machine.old."
		errorcode="2"
		status="failure"
		exit 2
	fi
fi
mv "$MACHINE/machine/" "$PREDIXHOME/machine/">>"$LOG" 2>&1

if [ $? -eq 0 ]; then
	chmod +x "$PREDIXHOME/machine/bin/predix/predixmachine"
	message="Machine application updated."
	errorcode="0"
	status="success"
	exit 0
else
	message="Machine application could not be updated."
	errorcode="3"
	status="failure"
	exit 3
fi