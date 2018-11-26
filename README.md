# Script-Packaging-Module
PowerShell Module to help package a PowerShell script or script resorces 

### Installing
Download the current branch and import the ScriptPackage.psd1 file into PowerShell

Once imported you will have 5 new commands that you can use to package your script files 

### Convert-PS2XE

This Command uses the famous [ps2exe](https://gallery.technet.microsoft.com/scriptcenter/PS2EXE-GUI-Convert-e7cb69d5) script 
to convert a ps1 file into a exe file

### Convert-FileToBase64

This command will convert a file to base64 code and print the code to a txt file 

The below will convert the code back to the original file
```
  $BaseCode = @" <CodeFromTextFile> "@  or $BaseCode = Get-Content <PathToTextFile>
  Set-Content -Path "<NameOforiginalFile>" -Value $BaseCode -Encoding Byte
```

### Convert-FileToDLL

This command will encrypt a file using AES 256 bit encryption to a dll file and will generate a key printed to a txt file that can be used to decypt the file

You can use the fallowing to decypt the file and run it from another PowerShell script
```
    $Path = <Path to DLL>
    trap { "Decryption failed"; break }
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
