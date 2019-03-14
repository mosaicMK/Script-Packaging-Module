# Script-Packaging-Module
PowerShell Module to help package a PowerShell script or script resorces 

### Installing
Download the current branch and import the ScriptPackage.psd1 file into PowerShell
or you can install the module from our PowerShell Gallery repository
https://www.powershellgallery.com/packages/ScriptPackaging/

Once imported run get-Command -Module ScriptPackaging

### Whats New

## Convert-PS2EXE
Removed all .net 3.5 and lower options from Convert-PS2EXE, This is to reduces the complexity of the function and to promote
better security

Added the ability to change the progress bar color 

Added an optional switch to enable -Extract on the compiled exe

Added support for long path names 

## Convert-FileToBASE64

rewored the function to write the base64 code in blocks of 9000 bits instead of all at once. This makes the convertion proccess much
fast and way less memory heavy

## Convert-FileFromBase64

This is a new function based off Convert-ToBase64. This will convert the code back to a file in the same method

### Convert-PS2XE

This Command uses the famous [ps2exe](https://gallery.technet.microsoft.com/scriptcenter/PS2EXE-GUI-Convert-e7cb69d5) script 
to convert a ps1 file into a exe file

### Convert-FileToBase64

This command will convert a file to base64 code and print the code to a txt file 

The below will convert the code back to the original file
```
  $BaseCode = @" <CodeFromTextFile> "@
  Set-Content -Path "<NameOforiginalFile>" -Value $BaseCode -Encoding Byte
```

### Convert-FileToDLL

This command will encrypt a file using AES 256 bit encryption to a dll file and will generate a key printed to a txt file that can be used to decypt the file

You can use the following to decypt the file and run it from another PowerShell script
```
    $Path = <Path to DLL>
    $secure = Get-Content $path | ConvertTo-SecureString -Key (<Content of key file seperated by a ",">)
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    $script = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    Invoke-Expression $script
```
### Convert-StringToSecureString

This command will encrypt a string to a secure string providing you with a key and the options to export the string and key to a file

### New-AESKeyFile

This command will create a file that contains a AES key that can be used with Convert-FileToDll and Convert-StringToSecureString this way you can specify a key instead of using a randomly generated one everytime.

### Read-AESKey

Prints the AES key from a file to the host window allow the key to be pasted into a script or command
