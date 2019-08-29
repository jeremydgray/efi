#!/bin/bash
#============================
# efi_extension_attribute.sh
# jeremy gray, Omada Health, 2019
#
# a script to capture an EFI password to Jamf Extension Attribute.
# 
# disclaimer: i'm providing these scripts as-is, and don't have bandwidth to offer support or updates. 
#============================

if [ -d "/Users/administrator/Desktop" ]; then
	pwFile="/Users/administrator/Desktop/pwFile.txt"
elif [ -d "/private/var/administrator/Desktop" ]; then
	pwFile="/private/var/administrator/Desktop/pwFile.txt"
else
	echo "Could not find administrator account."
    exit 1
fi

result="$(cat "$pwFile")"

echo "<result>$result</result>"