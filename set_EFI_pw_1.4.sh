#!/bin/bash
#============================
# set_EFI_pw_1.4.sh
# jeremy gray, Omada Health, 2019
#
# a script to set a new, random EFI password. this will check for a default password set in $4 of the Jamf policy and a password stored in pwFile.txt.
# 
# both options are tested, and if one is verified, or if no EFI password is set, will generate a 10-character alphanumeric password, save it to a pwFile readable only by root, and set EFI password to it.
#
# use this script during deployment and also in Self Service to allow for arbitrary EFI rotation as needed.
#
# bonus points: create a Jamf Extension Attribute using efi_extension_attribute.sh to collect EFIs into your JSS.
#
# disclaimer: i'm providing these scripts as-is, and don't have bandwidth to offer support or updates. 
#============================

#--------- Exit codes
# 1: $4 is not set
# 2: administrator user may not exist
# 3: could not set pwFile path
# 4: could not change password
# 5: could not verify existing pw
# 6: generic error

#--------- Declare some vars
EFIVerified=""
newEFIpw=""
EFIisSet=0
logfile="/Library/Logs/[YourOrgHere]/JamfEFI.log"

#--------- Log function
function log () {
	echo $(date) "|" $1 $2 >> $logfile
}

log "---------- Starting EFI rotation..."

#--------- Check for $4
if [ -z "$4" ]; then 
	log 'Please set a value for $4 and try again.'
	exit 1
fi

#--------- Check for admin user
if [ ! -d "/Users/administrator" ] && [ ! -d "/private/var/administrator" ]; then
	log 'Please verify the user "administrator" exists and try again.'
	exit 2
fi

#--------- Set pwFile path
if [ -d "/Users/administrator" ]; then
	pwFile="/Users/administrator/Desktop/pwFile.txt"
elif [ -d "/private/var/administrator" ]; then
	pwFile="/private/var/administrator/Desktop/pwFile.txt"
else
	log "Could not set path to pwFile."
	exit 3
fi

#--------- Touch log
touch $logfile
log "Touched logfile at "$logfile
chmod 600 $logfile
log "Set chmod 600 to $logfile"

#--------- Check for EFI set
e="$(firmwarepasswd -check | cut -c 19)"
if [ $e == "Y" ]; then 
	EFIisSet=1
	log "EFI password is set"
fi

export exp_EFIisSet=${EFIisSet}

#--------- Set oldEFIpw
if [ -s "$pwFile" ]; then
	oldEFIpw="$(cat "$pwFile")"
elif [ -z $oldEFIpw ]; then
	oldEFIpw="$4"
else
	log "Something else went wrong."
	exit 6
fi

#--------- Log old EFI
log "Old EFI:" $oldEFIpw

#--------- Prepare oldEFI for expect block
export exp_oldEFI=${oldEFIpw}

#--------- Generate new EFI pw to file
function genNewEFI () {
	rm "$pwFile"
    newEFIpw="$(openssl rand -base64 8 |md5 |head -c10;echo)"
	log "New EFI:" $newEFIpw
	
	touch "$pwFile"
	echo "$newEFIpw" > "$pwFile"
	chmod 600 "$pwFile"
	log "Saved new EFI password to $pwFile and ran chmod 600"
}

#--------- Set new EFI pw
function setNewEFI () {
	expect -d <<'Done'
		log_user 0
		spawn firmwarepasswd -setpasswd
		set result ""
		
		if { $env(exp_EFIisSet) == 1 } {
			expect "Enter password:"
			send -- $env(exp_oldEFI)
			send -- "\r"
		}

		expect "Enter new password:"
		send -- $env(exp_newEFI)
		send -- "\r"

		expect "Re-enter new password:"
		send -- $env(exp_newEFI)
		send -- "\r"

		expect {
				"Passwords do not match." {
					set result "Failed"
				} -re ".*(Password changed.*)" {
					set result "Success"
				}
		}

		log_user 1
		puts $result
Done
}

#--------- MAIN
#--------- Verify we know current EFI pw
EFIVerified="$(expect <<'Done'
	log_user 0
	spawn firmwarepasswd -verify

	expect "Enter password:"
	send -- $env(exp_oldEFI)\r

	expect -re {\n(\S+orrect)}
	set result $expect_out(1,string)

	log_user 1
	puts $result	
Done
)"

if [ "$EFIVerified" = "Incorrect" ]; then
	log "Could not verify the existing password."
	exit 5
fi

function setAndReport () {
	genNewEFI
	export exp_newEFI="${newEFIpw}"
	success="$(setNewEFI)"
	if [ "$success" = "Success" ]; then
		log "It worked. OMG."
		log "Now we need to reboot."
		echo "New EFI: $exp_newEFI" # do this so new password echoes into Jamf policy log
		jamf recon
		exit 0
	else
		log "Bummer. No dice."
		exit 6
	fi
}

#--------- EFI was off
if [ $EFIisSet -eq 0 ]; then
	setAndReport
fi

#--------- EFI was already set and we know the old pw
if [ $EFIisSet -eq 1 ] && [ "$EFIVerified" = "Correct" ]; then
	setAndReport
fi

#--------- Generic error
log "Something else went wrong."
exit 6