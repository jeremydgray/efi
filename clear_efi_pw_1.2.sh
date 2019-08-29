#!/bin/bash
#============================
# clear_EFI_pw_1.2.sh
# jeremy gray, Omada Health, 2019
# 
# a script to remove a known EFI password. this will check for a default password set in $4 of the Jamf policy, a password stored in pwFile.txt, and a password you give at a prompt. 
# 
# all three options are tested, and if one is verified, it will be cleared.
#
# disclaimer: i'm providing this scripts as-is, and don't have bandwidth to offer support or updates. 
#============================

#--------- Exit codes
# 1: $4 is not set
# 2: administrator user may not exist
# 3: could not set pwFile path
# 5: could not verify existing pw
# 6: generic error

#--------- Declare some vars
logfile="/Library/Logs/OmadaIT/JamfEFI.log"
EFIVerified=""
EFIisSet=0

#--------- Log function
function log () {
	echo $(date) "|" $1 $2 >> $logfile
}

log "---------- Starting EFI clear..."

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

#--------- Get arbitrary old password
oldEFI_prompted=$(/usr/bin/osascript -e 'set oldEFI_prompted to the text returned of (display dialog "Please enter a passphrase to use this script." default answer "" with icon stop buttons {"Cancel", "Continue"} default button "Continue" with hidden answer)')

#--------- Check for EFI set
e="$(firmwarepasswd -check | cut -c 19)"
if [ $e == "Y" ]; then 
	EFIisSet=1
	log "EFI password is set"
fi

export exp_EFIisSet=${EFIisSet}

#--------- Gather old EFI candidates
declare -a candidates

candidates+=("$oldEFI_prompted")
candidates+=("$(cat "$pwFile")")
candidates+=("$4")

log "Old EFI passwords" "${candidates[@]}"

#--------- Prepare candidates for expect block
export exp_oldEFI=${candidates[@]}

#--------- MAIN
#--------- Verify we know current EFI pw
EFIVerified="$(expect -d <<'Done'
	log_user 0
	set result "Failed";
	set correct "--";

	for {set x 0} {$x < 3} {incr x 1} {
		set try [lindex $env(exp_oldEFI) $x]

		spawn firmwarepasswd -verify

		expect "Enter password:"
		send -- $try
		send -- "\r"

		expect {
			"Correct" {
				set result "Success";
				set correct "$try";
			}
		}
	}

	log_user 1

	puts $correct;
Done
)"

log "Verified EFI" "$EFIVerified"

function setAndReport () {
	success="$(clearEFI)"
	if [ "$success" = "Success" ]; then
    	rm $pwFile
		log "It worked. OMG. EFI password is cleared."
        jamf recon
		exit 0
	else
		log "Bummer. No dice. EFI password is still set."
		exit 6
	fi
}

#--------- Clear EFI
function clearEFI () {
	export exp_EFIVerified=$EFIVerified
	expect -d <<'Done'
		log_user 0
		spawn firmwarepasswd -delete
		set result ""
		
		if { $env(exp_EFIisSet) == 1 } {
			expect "Enter password:"
			send -- $env(exp_EFIVerified)
			send -- "\r"
		}

		expect {
				"Password incorrect" {
					set result "Failed"
				} -re ".*(Password removed.*)" {
					set result "Success"
				}
		}

		log_user 1
		puts $result
Done
}

#--------- EFI was off
if [ $EFIisSet -eq 0 ]; then
	log "EFI password was already disabled"
	exit 0
fi

#--------- EFI was already set and we know the old pw
if [ $EFIisSet -eq 1 ] && [ "$EFIVerified" != "--" ]; then
	setAndReport
fi

#--------- EFI was already set and we do not know the old pw
if [ "$EFIVerified" = "--" ]; then
	log "Could not verify the existing password."
	exit 5
fi

#--------- Generic error
log "Something else went wrong."
exit 6