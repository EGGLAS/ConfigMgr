# Author: Nicklas Eriksson
# Purpose: Clear registry keys that make AnyConnect fails during installation. Can be run as script per machine in ConfigMgr.
# Version: 1.0 - 2019-03-28


Try {

    $Keys=Get-ChildItem HKCR:Installer -Recurse -ErrorAction Stop | Get-ItemProperty -name ProductName -ErrorAction SilentlyContinue

}

Catch {
    New-PSDrive -Name HKCR -PSProvider registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
    $Keys=Get-ChildItem HKCR:Installer -Recurse | Get-ItemProperty -name ProductName -ErrorAction SilentlyContinue
    }

Finally { 
    foreach ($Key in $Keys) {

        if ($Key.ProductName -like "Cisco*") {

            Remove-Item $Key.PSPath -Force -Recurse

        }
     }

}
