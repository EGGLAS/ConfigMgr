# ConfigMgr / MASHIPA

In our opinon Mashipa is an real shining automation tool for HP machines, the idea came from several other people inside ConfigMgr community.
To download the needed drivers, firmware, bios or software for each model is done with HPs HPCMSL cmdlets.

The tool support both Windows 10 and 11.

Version history:
1.0 - 2021-02-11 - Nicklas Eriksson -  Script Edited and fixed Daniels crappy hack and slash code :)
1.1 - 2021-02-18 - Nicklas Eriksson - Added HPIA to download to HPIA Download instead to Root Directory, Added BIOSPwd should be copy to HPIA so BIOS upgrades can be run during OSD. 
1.2 - 2021-04-14 - Daniel GrÃ¥hns - Added check if Offline folder is created
1.3 - 2021-04-27 - Nicklas Eriksson - Completed the function so the script also downloaded BIOS updates during sync.
1.4 - 2021-05-21 - Nicklas Eriksson & Daniel GrÃ¥hns - Changed the logic for how to check if the latest HPIA is downloaded or not since HP changed the how the set the name for HPIA.
1.5 - 2021-06-10 - Nicklas Eriksson - Added check to see that folder path exists in ConfigMgr otherwise creat the folder path.
1.6 - 2021-06-17 - Nicklas Eriksson - Added -Quiet to Invoke-RepositorySync, added max log size so the log file will rollover.
1.7 - 2021-06-18 - Nicklas Eriksson & Daniel GrÃ¥hns - Added if it's the first time the model is running skip filewatch.
1.8 - 2022-02-09 - Modified by Marcus Wahlstam, Advitum AB <marcus.wahlstam@advitum.se>
  - Fancier console output (see Print function)
  - Updated Config XML with more correct settings names
  - Removed unused code
  - Windows 11 support
  - Changed folder structure of the repository, both disk level and in CM (to support both Windows 10 and 11 and to make repository cleaner)
  - Added migration check - will migrate old structure to the new structure (both disk level and CM)
  - Changed how repository filters are handled in the script
  - Added function to check if module is updated or not before trying to update it
  - Fixed broken check if HPIA was updated or not (will now check value of FileVersionInfo.FileVersion on HPImageassistant.exe)
  - Changed csv format of supported models, added column "WindowsVersion" (set to Win10 or Win11)
  - Changed format of package name to include WindowsVersion (Win10 or Win11)
  - Offline cache folder is now checked 10 times if it exists (while loop)
  - Added progress bar to show which model is currently processed and how many there are left
2.0 - 2022-03-22 - Nicklas Eriksson, Daniel Grahns and Rickard Lundberg
  - Added Register-PSRepo
  - Updated Roboycopy syntax
  - Made Migration to new structure optional and which OS you want to migrate to new folder structure (Use this only if you have Windows 10 as only OS and not started with Windows 11 since the old naming structure did not contain OS Version.)
  - Removed unused code
  - Added more logging
  - Added more error handling to catch the errors to the log file.


You running this script/function means you will not blame the author(s) if this breaks your stuff. This script/function is provided AS IS without warranty of any kind. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
In no event shall author(s) be held liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the script or documentation. 
Simply put: Use at your own risk.
