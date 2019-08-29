# EFI Deployment, Rotation, Clearing, and Documentation
### A mechanism to set, clear, and manage EFI passwords for Mac via Jamf

## The Puzzle:
We want to deploy Macs with EFI passwords set to prevent users from booting to Target Disk Mode or to other boot volumes. Jamf provides a uniform EFI password mechanism, but we don't want to give this out to our end users, as they would now know the single password for all of our machines. 

Instead, we want to give all machines their own unique EFI passwords that are known to IT but unknown to the end user. When delivering support, especially remotely, we want to provide the end user their own EFI password as needed, and then have the ability to rotate the EFI password to a new one on demand.

## The Solution:
I hacked together an `expect` script to interact with Apple's `firmwarepasswd` utility, wrapped in Bash. 

On first run during deployment, `set_EFI_pw_1.4.sh` generates a new password, sets it, writes it to a file, `chmod 600` the file (root visible only), and echoes the new password to the Jamf policy log (this allows us password history in case something goes wrong).

On subsequent runs, the script will look in the Jamf policy (in $4) for any default EFI password (in our example, the old single EFI password) and for the EFI password that was set during the most recent run. It verifies one of those passwords is correct, then generates and sets a new one.

Once set, the script runs a `jamf recon` to allow `efi_extension_attribute.sh` to read and catch the EFI password to display it in the JSS.

Finally, when a machine needs to be wiped and its record removed from the JSS, we clear the EFI password using `clear_efi_pw_1.2.sh`. We fire the script using a Self Service policy scoped to all machines, but limited to IT team members. IT must log into Self Service to make the policy visible.

Here it is all together:
- Put `efi_extension_attribute.sh` into your JSS at Settings > Computer Management > Extension Attributes, scoped to all.
- Run `set_EFI_pw_1.4.sh` during provisioning with a restart payload in the policy (we do this in our PreStage Enrollments).
- Put `set_EFI_pw_1.4.sh` with a restart payload into a Self Service policy scoped to all. Users can run this as often as they want without any repercussions.
- Put `clear_efi_pw_1.2.sh` with a restart payload into a Self Service, scoped to all, but limited to members of IT only. We do this so that machines ready for de/re-provisioning can be cleared, without allowing end users to remove EFI passwords themselves.

## Gotchas 
We've noticed that order of operations is important, particularly when clearing a password. The EFI password lives in three places:
- `pwFile.txt` (by default, I'm keeping this at `/Users/administrator/Desktop`)
- JSS Extentension Attribute
- JSS Policy Log

Keep in mind that both the `set` and `clear` scripts require that `pwFile.txt` exists. If you delete this file or it becomes otherwise lost, the scripts will fail. 
Also, the next time `jamf recon` runs, it will see no `pwFile.txt` and drop the password out of the Extension Attribute.
And if you remove the machine from the JSS, you will lose policy history and the Extension Attribute containing the active password.
If you lose all three, you'll need Apple to clear the EFI password however they do that.
Be careful.

## Reuse
This was a fun and useful project, so I'm offering it to the community to play with and deploy as you see fit. I'm not in a position to offer any ongoing support, and may never update this again. Please feel free to fork and mutate as you wish. Use at your own risk.
