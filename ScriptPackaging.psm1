function Convert-PS2EXE {
<#
.SYNOPSIS
Create an exe file from a PowerShell script file
.DESCRIPTION
A generated executables has the following reserved parameters:

-debug Forces the executable to be debugged. It calls "System.Diagnostics.Debugger.Break()".The script will not be executed.
-wait At the end of the script execution it writes "Hit any key to exit..." and waits for a key to be pressed.
-end All following options will be passed to the script inside the executable. All preceding options are used by the executable itself and will not be passed to the script
-Extract extracts the content of the exe to a file, This switch will only be present if the -AllowExtract option was used during the build proccess, 

Script variables:
Since PS2EXE converts a script to an executable, script related variables are not available anymore. 
Especially the variable $PSScriptRoot and variable $MyInvocation is set to other values than in a script.
You can retrieve the script/executable path independant of compiled/not compiled with the following code:
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript"){ $ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition }else{ $ScriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0]) }

Exit Codes:
At this time using the Exit <number> method of setting an exit code will not fill $LASTEXITCODE in the parrent proccess if you need to get an exit code 
We recomend having the script write the code to the registry or a temp file for the parrent proccess to access 

.PARAMETER inputFile
Powershell script that you want to convert to EXE
.PARAMETER outputFile
destination EXE file name
.PARAMETER VerboseBuild
output verbose informations - if any
.PARAMETER DebugBuild
generate debug informations for output file
.PARAMETER lcid
location ID for the compiled EXE. Current user culture if not specified
.PARAMETER platform
compile for the choice platform (x86, x64, anycpu)
.PARAMETER sta
Single Thread Apartment Mode
.PARAMETER mta
Multi Thread Apartment Mode
.PARAMETER noConsole
the resulting EXE file will be a Windows Forms app without a console window.
The GUI expanded every output and input function like Write-Host, Write-Output, Write-Error,
Out-Default, Prompt, ReadLine to use WinForms message boxes or input boxes automatically when compiling a GUI application.
Per default output of commands are formatted line per line (as an array of strings).
When your command generates 10 lines of output and you use GUI output, 10 message boxes will appear each awaitung for an OK.
To prevent this pipe your command to the comandlet Out-String. This will convert the output to a string array with 10 lines,
all output will be shown in one message box (for example: dir C:\ | Out-String).
.PARAMETER credentialGUI
use GUI for prompting credentials in console mode
.PARAMETER iconFile
icon file name for the compiled EXE
.PARAMETER title
title information (displayed in details tab of Windows Explorer's properties dialog)
.PARAMETER description
description information (not displayed, but embedded in executable)
.PARAMETER company
company information (not displayed, but embedded in executable)
.PARAMETER product
product information (displayed in details tab of Windows Explorer's properties dialog)
.PARAMETER copyright
copyright information (displayed in details tab of Windows Explorer's properties dialog)
.PARAMETER trademark
trademark information (displayed in details tab of Windows Explorer's properties dialog)
.PARAMETER version
version information (displayed in details tab of Windows Explorer's properties dialog)
.PARAMETER noConfigfile
write no config file (<outputfile>.exe.config)
.PARAMETER requireAdmin
if UAC is enabled, compiled EXE run only in elevated context (UAC dialog appears if required)
.PARAMETER virtualize
application virtualization is activated (forcing x86 runtime)
.PARAMETER ProgressBarColor
Specify the color used for a progress bar (Write-Progress)
.PARAMETER AllowExtract
Use this to add the -Extract Paramiter to the compiled exe
.PARAMETER LongPaths
Enables the use of paths longer then 265 characters
.Example
Convert-PS2EXE -inputFile c:\script.ps1 -outputFile C:\script.exe -noConsole -noConfigfile -iconFile c:\file.ico -title "script"
Creates a exe file named script.exe that wont show a powershell console using the file.ico file
.Notes
PS2EXE-GUI v0.5.0.14
Written by: Ingo Karstein (http://blog.karstein-consulting.com)
Reworked and GUI support by Markus Scholtes
Module intagration and Help syntax created by MosaicMK Software LLC (https://www.mosaicmk.com) or (https://blog.mosaicmk.com)
Origanal script can be found https://gallery.technet.microsoft.com/scriptcenter/PS2EXE-GUI-Convert-e7cb69d5
This script is released under Microsoft Public Licence
that can be downloaded here: https://opensource.org/licenses/MS-PL
.link
https://www.mosaicmk.com
#>

Param(
	[Parameter(Mandatory=$true)]
	[string]$inputFile,
	[Parameter(Mandatory=$true)]
	[string]$outputFile,
	[switch]$VerboseBuild,
	[switch]$DebugBuild,
	[Parameter(Mandatory=$true)]
	[ValidateSet('x64','x86','anycpu')]
	[string]$platform,
	[int]$lcid,
	[switch]$Sta,
	[switch]$Mta,
	[switch]$NoConsole,
	[string]$IconFile=$null,
	[string]$Title,
	[string]$Description,
	[string]$Company,
	[string]$Product,
	[string]$Copyright,
	[string]$Trademark,
	[string]$Version,
	[switch]$RequireAdmin,
	[switch]$Virtualize,
	[switch]$CredentialGUI,
	[switch]$NoConfigfile,
	[switch]$AllowExtract,
	[string]$ProgressBarColor = "DarkGreen",
	[switch]$longPaths
)
IF ($AllowExtract){$ExtractString = @"
								else if (s.StartsWith("-extract", StringComparison.InvariantCultureIgnoreCase))
							{
								string[] s1 = s.Split(new string[] { ":" }, 2, StringSplitOptions.RemoveEmptyEntries);
								if (s1.Length != 2)
								{
$(if (!$noConsole) {@"
									Console.WriteLine("If you specify the -extract option you need to add a file for extraction in this way\r\n   -extract:\"<filename>\"");
"@ } else {@"
									MessageBox.Show("If you specify the -extract option you need to add a file for extraction in this way\r\n   -extract:\"<filename>\"", System.AppDomain.CurrentDomain.FriendlyName, MessageBoxButtons.OK, MessageBoxIcon.Error);
"@ })
									return 1;
								}
								extractFN = s1[1].Trim(new char[] { '\"' });
							}

"@
}
$runtime40 = $true
Function Stop-Error {
	PARAM(
		$Message,
		$ExitCode
	)
	Write-Error $Message
	Exit $ExitCode
}

if ($Sta -and $Mta){Stop-Error -Message "The switches -Sta and -Mta at the same time" -ExitCode 1}
if ($requireAdmin -and $virtualize){Stop-Error -Message "-requireAdmin cannot be combined with -virtualize" -ExitCode 1}
$psversion = 0
if ($PSVersionTable.PSVersion.Major -ge 4){$psversion = 4} Else {Stop-Error -Message "PowerShell 4.0 or newer not installed" -ExitCode 3}
if ($psversion -eq 0){Stop-Error -Message "The powershell version is unknown!" -ExitCode 1}

# retrieve absolute paths independent whether path is given relative oder absolute
$inputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($inputFile)
$outputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outputFile)

if (!(Test-Path $inputFile -PathType Leaf)){Stop-Error -Message "Input file $($inputfile) not found!" -ExitCode 1}

if ($iconFile){$iconFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($iconFile)
if (!(Test-Path $iconFile -PathType Leaf)){Stop-Error -Message "Icon file $($iconFile) not found!" -ExitCode 1}}

if ($noConfigfile -and $longPaths){Write-Warning "Option -noConfigfile disables -longPaths"}

if (!$Mta -and !$Sta){$Sta = $TRUE}
$title = $title -replace "\\", "\\"
$product = $product -replace "\\", "\\"
$copyright = $copyright -replace "\\", "\\"
$trademark = $trademark -replace "\\", "\\"
$description = $description -replace "\\", "\\"
$company = $company -replace "\\", "\\"

$type = ('System.Collections.Generic.Dictionary`2') -as "Type"
$type = $type.MakeGenericType( @( ("System.String" -as "Type"), ("system.string" -as "Type") ) )
$o = [Activator]::CreateInstance($type)

$compiler20 = $FALSE
$o.Add("CompilerVersion", "v4.0")

$referenceAssembies = @("System.dll")
if (!$noConsole){
	if ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.Name -ieq "Microsoft.PowerShell.ConsoleHost.dll" }){
		$referenceAssembies += ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.Name -ieq "Microsoft.PowerShell.ConsoleHost.dll" } | Select-Object -First 1).Location
	}
}
$referenceAssembies += ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.Name -ieq "System.Management.Automation.dll" } | Select-Object -First 1).Location

if ($runtime40){
	$n = New-Object System.Reflection.AssemblyName("System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089")
	[System.AppDomain]::CurrentDomain.Load($n) | Out-Null
	$referenceAssembies += ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.Name -ieq "System.Core.dll" } | Select-Object -First 1).Location
}

if ($noConsole){
	$n = New-Object System.Reflection.AssemblyName("System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089")
	if ($runtime40){$n = New-Object System.Reflection.AssemblyName("System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089")}
	[System.AppDomain]::CurrentDomain.Load($n) | Out-Null
	$n = New-Object System.Reflection.AssemblyName("System.Drawing, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a")
	if ($runtime40){$n = New-Object System.Reflection.AssemblyName("System.Drawing, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a")}
	[System.AppDomain]::CurrentDomain.Load($n) | Out-Null
	$referenceAssembies += ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.Name -ieq "System.Windows.Forms.dll" } | Select-Object -First 1).Location
	$referenceAssembies += ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.Name -ieq "System.Drawing.dll" } | Select-Object -First 1).Location
}

$cop = (New-Object Microsoft.CSharp.CSharpCodeProvider($o))
$cp = New-Object System.CodeDom.Compiler.CompilerParameters($referenceAssembies, $outputFile)
$cp.GenerateInMemory = $FALSE
$cp.GenerateExecutable = $TRUE

$iconFileParam = ""
if ($iconFile){$iconFileParam = "`"/win32icon:$($iconFile)`""}

$manifestParam = ""
if ($requireAdmin -or $longPaths){
	$manifestParam = "`"/win32manifest:$($outputFile+".win32manifest")`""
	$win32manifest = "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>`r`n<assembly xmlns=""urn:schemas-microsoft-com:asm.v1"" manifestVersion=""1.0"">`r`n"
	if ($longPaths){$win32manifest += "<application xmlns=""urn:schemas-microsoft-com:asm.v3"">`r`n<windowsSettings>`r`n<longPathAware xmlns=""http://schemas.microsoft.com/SMI/2016/WindowsSettings"">true</longPathAware>`r`n</windowsSettings>`r`n</application>`r`n"}
	if ($requireAdmin){$win32manifest += "<trustInfo xmlns=""urn:schemas-microsoft-com:asm.v2"">`r`n<security>`r`n<requestedPrivileges xmlns=""urn:schemas-microsoft-com:asm.v3"">`r`n<requestedExecutionLevel level=""requireAdministrator"" uiAccess=""false""/>`r`n</requestedPrivileges>`r`n</security>`r`n</trustInfo>`r`n"}
	$win32manifest += "</assembly>"
	$win32manifest | Set-Content ($outputFile+".win32manifest") -Encoding UTF8
}

if (!$virtualize){ $cp.CompilerOptions = "/platform:$($platform) /target:$( if ($noConsole){'winexe'}else{'exe'}) $($iconFileParam) $($manifestParam)" }else{ 
	$cp.CompilerOptions = "/platform:x86 /target:$( if ($noConsole) { 'winexe' } else { 'exe' } ) /nowin32manifest $($iconFileParam)"}

$cp.IncludeDebugInformation = $DebugBuild

if ($DebugBuild){$cp.TempFiles.KeepFiles = $TRUE}


$content = Get-Content -LiteralPath ($inputFile) -Encoding UTF8 -ErrorAction SilentlyContinue
$scriptInp = [string]::Join("`r`n", $content)
$script = [System.Convert]::ToBase64String(([System.Text.Encoding]::UTF8.GetBytes($scriptInp)))

#region program frame
$culture = ""

if ($lcid){
$culture = @"
System.Threading.Thread.CurrentThread.CurrentCulture = System.Globalization.CultureInfo.GetCultureInfo($lcid);
System.Threading.Thread.CurrentThread.CurrentUICulture = System.Globalization.CultureInfo.GetCultureInfo($lcid);
"@
}

$programFrame = @"
using System;
using System.Collections.Generic;
using System.Text;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using PowerShell = System.Management.Automation.PowerShell;
using System.Globalization;
using System.Management.Automation.Host;
using System.Security;
using System.Reflection;
using System.Runtime.InteropServices;
$(if ($noConsole) {@"
using System.Windows.Forms;
using System.Drawing;
"@ })

[assembly:AssemblyTitle("$title")]
[assembly:AssemblyProduct("$product")]
[assembly:AssemblyCopyright("$copyright")]
[assembly:AssemblyTrademark("$trademark")]
$(if (![string]::IsNullOrEmpty($version)) {@"
[assembly:AssemblyVersion("$version")]
[assembly:AssemblyFileVersion("$version")]
"@ })
[assembly:AssemblyDescription("$description")]
[assembly:AssemblyCompany("$company")]

namespace ik.PowerShell
{
$(if ($noConsole -or $credentialGUI) {@"
	internal class CredentialForm
	{
		[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
		private struct CREDUI_INFO
		{
			public int cbSize;
			public IntPtr hwndParent;
			public string pszMessageText;
			public string pszCaptionText;
			public IntPtr hbmBanner;
		}

		[Flags]
		enum CREDUI_FLAGS
		{
			INCORRECT_PASSWORD = 0x1,
			DO_NOT_PERSIST = 0x2,
			REQUEST_ADMINISTRATOR = 0x4,
			EXCLUDE_CERTIFICATES = 0x8,
			REQUIRE_CERTIFICATE = 0x10,
			SHOW_SAVE_CHECK_BOX = 0x40,
			ALWAYS_SHOW_UI = 0x80,
			REQUIRE_SMARTCARD = 0x100,
			PASSWORD_ONLY_OK = 0x200,
			VALIDATE_USERNAME = 0x400,
			COMPLETE_USERNAME = 0x800,
			PERSIST = 0x1000,
			SERVER_CREDENTIAL = 0x4000,
			EXPECT_CONFIRMATION = 0x20000,
			GENERIC_CREDENTIALS = 0x40000,
			USERNAME_TARGET_CREDENTIALS = 0x80000,
			KEEP_USERNAME = 0x100000,
		}

		public enum CredUIReturnCodes
		{
			NO_ERROR = 0,
			ERROR_CANCELLED = 1223,
			ERROR_NO_SUCH_LOGON_SESSION = 1312,
			ERROR_NOT_FOUND = 1168,
			ERROR_INVALID_ACCOUNT_NAME = 1315,
			ERROR_INSUFFICIENT_BUFFER = 122,
			ERROR_INVALID_PARAMETER = 87,
			ERROR_INVALID_FLAGS = 1004,
		}

		[DllImport("credui", CharSet = CharSet.Unicode)]
		private static extern CredUIReturnCodes CredUIPromptForCredentials(ref CREDUI_INFO creditUR,
			string targetName,
			IntPtr reserved1,
			int iError,
			StringBuilder userName,
			int maxUserName,
			StringBuilder password,
			int maxPassword,
			[MarshalAs(UnmanagedType.Bool)] ref bool pfSave,
			CREDUI_FLAGS flags);

		public class UserPwd
		{
			public string User = string.Empty;
			public string Password = string.Empty;
			public string Domain = string.Empty;
		}

		internal static UserPwd PromptForPassword(string caption, string message, string target, string user, PSCredentialTypes credTypes, PSCredentialUIOptions options)
		{
			StringBuilder userPassword = new StringBuilder(), userID = new StringBuilder(user, 128);
			CREDUI_INFO credUI = new CREDUI_INFO();
			if (!string.IsNullOrEmpty(message)) credUI.pszMessageText = message;
			if (!string.IsNullOrEmpty(caption)) credUI.pszCaptionText = caption;
			credUI.cbSize = Marshal.SizeOf(credUI);
			bool save = false;

			CREDUI_FLAGS flags = CREDUI_FLAGS.DO_NOT_PERSIST;
			if ((credTypes & PSCredentialTypes.Generic) == PSCredentialTypes.Generic)
			{
				flags |= CREDUI_FLAGS.GENERIC_CREDENTIALS;
				if ((options & PSCredentialUIOptions.AlwaysPrompt) == PSCredentialUIOptions.AlwaysPrompt)
				{
					flags |= CREDUI_FLAGS.ALWAYS_SHOW_UI;
				}
			}

			CredUIReturnCodes returnCode = CredUIPromptForCredentials(ref credUI, target, IntPtr.Zero, 0, userID, 128, userPassword, 128, ref save, flags);

			if (returnCode == CredUIReturnCodes.NO_ERROR)
			{
				UserPwd ret = new UserPwd();
				ret.User = userID.ToString();
				ret.Password = userPassword.ToString();
				ret.Domain = "";
				return ret;
			}

			return null;
		}
	}
"@ })

	internal class PS2EXEHostRawUI : PSHostRawUserInterface
	{
$(if ($noConsole){ @"
		private ConsoleColor ncBackgroundColor = ConsoleColor.White;
		private ConsoleColor ncForegroundColor = ConsoleColor.Black;
"@ } else {@"
		const int STD_OUTPUT_HANDLE = -11;

		[StructLayout(LayoutKind.Explicit)]
		public struct CHAR_INFO
		{
			[FieldOffset(0)]
			internal char UnicodeChar;
			[FieldOffset(0)]
			internal char AsciiChar;
			[FieldOffset(2)] //2 bytes seems to work properly
			internal UInt16 Attributes;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct COORD
		{
			public short X;
			public short Y;
		}

		[StructLayout(LayoutKind.Sequential)]
		public struct SMALL_RECT
		{
			public short Left;
			public short Top;
			public short Right;
			public short Bottom;
		}

		[DllImport("kernel32.dll", EntryPoint = "ReadConsoleOutputW", CharSet = CharSet.Unicode, SetLastError = true)]
		internal static extern bool ReadConsoleOutput(
			IntPtr hConsoleOutput,
			/* This pointer is treated as the origin of a two-dimensional array of CHAR_INFO structures
			whose size is specified by the dwBufferSize parameter.*/
			[MarshalAs(UnmanagedType.LPArray), Out] CHAR_INFO[,] lpBuffer,
			COORD dwBufferSize,
			COORD dwBufferCoord,
			ref SMALL_RECT lpReadRegion);

		[DllImport("kernel32.dll", EntryPoint = "WriteConsoleOutputW", CharSet = CharSet.Unicode, SetLastError = true)]
		internal static extern bool WriteConsoleOutput(
			IntPtr hConsoleOutput,
			/* This pointer is treated as the origin of a two-dimensional array of CHAR_INFO structures
			whose size is specified by the dwBufferSize parameter.*/
			[MarshalAs(UnmanagedType.LPArray), In] CHAR_INFO[,] lpBuffer,
			COORD dwBufferSize,
			COORD dwBufferCoord,
			ref SMALL_RECT lpWriteRegion);

		[DllImport("kernel32.dll", SetLastError = true)]
		static extern bool ScrollConsoleScreenBuffer(
			IntPtr hConsoleOutput,
			[In] ref SMALL_RECT lpScrollRectangle,
			[In] ref SMALL_RECT lpClipRectangle,
			COORD dwDestinationOrigin,
			[In] ref CHAR_INFO lpFill);

		[DllImport("kernel32.dll", SetLastError = true)]
			static extern IntPtr GetStdHandle(int nStdHandle);
"@ })

		public override ConsoleColor BackgroundColor
		{
$(if (!$noConsole){ @"
			get
			{
				return Console.BackgroundColor;
			}
			set
			{
				Console.BackgroundColor = value;
			}
"@ } else {@"
			get
			{
				return ncBackgroundColor;
			}
			set
			{
				ncBackgroundColor = value;
			}
"@ })
		}

		public override System.Management.Automation.Host.Size BufferSize
		{
			get
			{
$(if (!$noConsole){ @"
				if (ConsoleInfo.IsOutputRedirected())
					return new System.Management.Automation.Host.Size(120, 50);
				else
					return new System.Management.Automation.Host.Size(Console.BufferWidth, Console.BufferHeight);
"@ } else {@"
				return new System.Management.Automation.Host.Size(120, 50);
"@ })
			}
			set
			{
$(if (!$noConsole){ @"
				Console.BufferWidth = value.Width;
				Console.BufferHeight = value.Height;
"@ })
			}
		}

		public override Coordinates CursorPosition
		{
			get
			{
$(if (!$noConsole){ @"
				return new Coordinates(Console.CursorLeft, Console.CursorTop);
"@ } else {@"
				return new Coordinates(0, 0);
"@ })
			}
			set
			{
$(if (!$noConsole){ @"
				Console.CursorTop = value.Y;
				Console.CursorLeft = value.X;
"@ })
			}
		}

		public override int CursorSize
		{
			get
			{
$(if (!$noConsole){ @"
				return Console.CursorSize;
"@ } else {@"
				return 25;
"@ })
			}
			set
			{
$(if (!$noConsole){ @"
				Console.CursorSize = value;
"@ })
			}
		}

$(if ($noConsole){ @"
		private Form InvisibleForm = null;
"@ })

		public override void FlushInputBuffer()
		{
$(if (!$noConsole){ @"
			if (!ConsoleInfo.IsInputRedirected())
			{	while (Console.KeyAvailable)
    			Console.ReadKey(true);
    	}
"@ } else {@"
			if (InvisibleForm != null)
			{
				InvisibleForm.Close();
				InvisibleForm = null;
			}
			else
			{
				InvisibleForm = new Form();
				InvisibleForm.Opacity = 0;
				InvisibleForm.ShowInTaskbar = false;
				InvisibleForm.Visible = true;
			}
"@ })
		}

		public override ConsoleColor ForegroundColor
		{
$(if (!$noConsole){ @"
			get
			{
				return Console.ForegroundColor;
			}
			set
			{
				Console.ForegroundColor = value;
			}
"@ } else {@"
			get
			{
				return ncForegroundColor;
			}
			set
			{
				ncForegroundColor = value;
			}
"@ })
		}

		public override BufferCell[,] GetBufferContents(System.Management.Automation.Host.Rectangle rectangle)
		{
$(if ($compiler20) {@"
			throw new Exception("Method GetBufferContents not implemented for .Net V2.0 compiler");
"@ } else { if (!$noConsole) {@"
			IntPtr hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
			CHAR_INFO[,] buffer = new CHAR_INFO[rectangle.Bottom - rectangle.Top + 1, rectangle.Right - rectangle.Left + 1];
			COORD buffer_size = new COORD() {X = (short)(rectangle.Right - rectangle.Left + 1), Y = (short)(rectangle.Bottom - rectangle.Top + 1)};
			COORD buffer_index = new COORD() {X = 0, Y = 0};
			SMALL_RECT screen_rect = new SMALL_RECT() {Left = (short)rectangle.Left, Top = (short)rectangle.Top, Right = (short)rectangle.Right, Bottom = (short)rectangle.Bottom};

			ReadConsoleOutput(hStdOut, buffer, buffer_size, buffer_index, ref screen_rect);

			System.Management.Automation.Host.BufferCell[,] ScreenBuffer = new System.Management.Automation.Host.BufferCell[rectangle.Bottom - rectangle.Top + 1, rectangle.Right - rectangle.Left + 1];
			for (int y = 0; y <= rectangle.Bottom - rectangle.Top; y++)
				for (int x = 0; x <= rectangle.Right - rectangle.Left; x++)
				{
					ScreenBuffer[y,x] = new System.Management.Automation.Host.BufferCell(buffer[y,x].AsciiChar, (System.ConsoleColor)(buffer[y,x].Attributes & 0xF), (System.ConsoleColor)((buffer[y,x].Attributes & 0xF0) / 0x10), System.Management.Automation.Host.BufferCellType.Complete);
				}

			return ScreenBuffer;
"@ } else {@"
			System.Management.Automation.Host.BufferCell[,] ScreenBuffer = new System.Management.Automation.Host.BufferCell[rectangle.Bottom - rectangle.Top + 1, rectangle.Right - rectangle.Left + 1];

			for (int y = 0; y <= rectangle.Bottom - rectangle.Top; y++)
				for (int x = 0; x <= rectangle.Right - rectangle.Left; x++)
				{
					ScreenBuffer[y,x] = new System.Management.Automation.Host.BufferCell(' ', ncForegroundColor, ncBackgroundColor, System.Management.Automation.Host.BufferCellType.Complete);
				}

			return ScreenBuffer;
"@ } })
		}

		public override bool KeyAvailable
		{
			get
			{
$(if (!$noConsole) {@"
				return Console.KeyAvailable;
"@ } else {@"
				return true;
"@ })
			}
		}

		public override System.Management.Automation.Host.Size MaxPhysicalWindowSize
		{
			get
			{
$(if (!$noConsole){ @"
				return new System.Management.Automation.Host.Size(Console.LargestWindowWidth, Console.LargestWindowHeight);
"@ } else {@"
				return new System.Management.Automation.Host.Size(240, 84);
"@ })
			}
		}

		public override System.Management.Automation.Host.Size MaxWindowSize
		{
			get
			{
$(if (!$noConsole){ @"
				return new System.Management.Automation.Host.Size(Console.BufferWidth, Console.BufferWidth);
"@ } else {@"
				return new System.Management.Automation.Host.Size(120, 84);
"@ })
			}
		}

		public override KeyInfo ReadKey(ReadKeyOptions options)
		{
$(if (!$noConsole) {@"
			ConsoleKeyInfo cki = Console.ReadKey((options & ReadKeyOptions.NoEcho)!=0);

			ControlKeyStates cks = 0;
			if ((cki.Modifiers & ConsoleModifiers.Alt) != 0)
				cks |= ControlKeyStates.LeftAltPressed | ControlKeyStates.RightAltPressed;
			if ((cki.Modifiers & ConsoleModifiers.Control) != 0)
				cks |= ControlKeyStates.LeftCtrlPressed | ControlKeyStates.RightCtrlPressed;
			if ((cki.Modifiers & ConsoleModifiers.Shift) != 0)
				cks |= ControlKeyStates.ShiftPressed;
			if (Console.CapsLock)
				cks |= ControlKeyStates.CapsLockOn;
			if (Console.NumberLock)
				cks |= ControlKeyStates.NumLockOn;

			return new KeyInfo((int)cki.Key, cki.KeyChar, cks, (options & ReadKeyOptions.IncludeKeyDown)!=0);
"@ } else {@"
			if ((options & ReadKeyOptions.IncludeKeyDown)!=0)
				return ReadKeyBox.Show("", "", true);
			else
				return ReadKeyBox.Show("", "", false);
"@ })
		}

		public override void ScrollBufferContents(System.Management.Automation.Host.Rectangle source, Coordinates destination, System.Management.Automation.Host.Rectangle clip, BufferCell fill)
		{
$(if (!$noConsole) { if ($compiler20) {@"
			throw new Exception("Method ScrollBufferContents not implemented for .Net V2.0 compiler");
"@ } else {@"
			if ((source.Left > clip.Right) || (source.Right < clip.Left) || (source.Top > clip.Bottom) || (source.Bottom < clip.Top))
			{
				return;
			}

			IntPtr hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
			SMALL_RECT lpScrollRectangle = new SMALL_RECT() {Left = (short)source.Left, Top = (short)source.Top, Right = (short)(source.Right), Bottom = (short)(source.Bottom)};
			SMALL_RECT lpClipRectangle;
			if (clip != null)
			{ lpClipRectangle = new SMALL_RECT() {Left = (short)clip.Left, Top = (short)clip.Top, Right = (short)(clip.Right), Bottom = (short)(clip.Bottom)}; }
			else
			{ lpClipRectangle = new SMALL_RECT() {Left = (short)0, Top = (short)0, Right = (short)(Console.WindowWidth - 1), Bottom = (short)(Console.WindowHeight - 1)}; }
			COORD dwDestinationOrigin = new COORD() {X = (short)(destination.X), Y = (short)(destination.Y)};
			CHAR_INFO lpFill = new CHAR_INFO() { AsciiChar = fill.Character, Attributes = (ushort)((int)(fill.ForegroundColor) + (int)(fill.BackgroundColor)*16) };

			ScrollConsoleScreenBuffer(hStdOut, ref lpScrollRectangle, ref lpClipRectangle, dwDestinationOrigin, ref lpFill);
"@ } })
		}

		public override void SetBufferContents(System.Management.Automation.Host.Rectangle rectangle, BufferCell fill)
		{
$(if (!$noConsole){ @"
			if (rectangle.Left >= 0)
				Console.MoveBufferArea(rectangle.Left, rectangle.Top, rectangle.Right-rectangle.Left+1, rectangle.Bottom-rectangle.Top+1, BufferSize.Width, BufferSize.Height, fill.Character, fill.ForegroundColor, fill.BackgroundColor);
			else
			{
				Console.MoveBufferArea(0, 0, BufferSize.Width, BufferSize.Height, BufferSize.Width, BufferSize.Height, fill.Character, fill.ForegroundColor, fill.BackgroundColor);
			}
"@ })
		}

		public override void SetBufferContents(Coordinates origin, BufferCell[,] contents)
		{
$(if (!$noConsole) { if ($compiler20) {@"
			throw new Exception("Method SetBufferContents not implemented for .Net V2.0 compiler");
"@ } else {@"
			IntPtr hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
			CHAR_INFO[,] buffer = new CHAR_INFO[contents.GetLength(0), contents.GetLength(1)];
			COORD buffer_size = new COORD() {X = (short)(contents.GetLength(1)), Y = (short)(contents.GetLength(0))};
			COORD buffer_index = new COORD() {X = 0, Y = 0};
			SMALL_RECT screen_rect = new SMALL_RECT() {Left = (short)origin.X, Top = (short)origin.Y, Right = (short)(origin.X + contents.GetLength(1) - 1), Bottom = (short)(origin.Y + contents.GetLength(0) - 1)};

			for (int y = 0; y < contents.GetLength(0); y++)
				for (int x = 0; x < contents.GetLength(1); x++)
				{
					buffer[y,x] = new CHAR_INFO() { AsciiChar = contents[y,x].Character, Attributes = (ushort)((int)(contents[y,x].ForegroundColor) + (int)(contents[y,x].BackgroundColor)*16) };
				}

			WriteConsoleOutput(hStdOut, buffer, buffer_size, buffer_index, ref screen_rect);
"@ } })
		}

		public override Coordinates WindowPosition
		{
			get
			{
				Coordinates s = new Coordinates();
$(if (!$noConsole){ @"
				s.X = Console.WindowLeft;
				s.Y = Console.WindowTop;
"@ } else {@"
				s.X = 0;
				s.Y = 0;
"@ })
				return s;
			}
			set
			{
$(if (!$noConsole){ @"
				Console.WindowLeft = value.X;
				Console.WindowTop = value.Y;
"@ })
			}
		}

		public override System.Management.Automation.Host.Size WindowSize
		{
			get
			{
				System.Management.Automation.Host.Size s = new System.Management.Automation.Host.Size();
$(if (!$noConsole){ @"
				s.Height = Console.WindowHeight;
				s.Width = Console.WindowWidth;
"@ } else {@"
				s.Height = 50;
				s.Width = 120;
"@ })
				return s;
			}
			set
			{
$(if (!$noConsole){ @"
				Console.WindowWidth = value.Width;
				Console.WindowHeight = value.Height;
"@ })
			}
		}

		public override string WindowTitle
		{
			get
			{
$(if (!$noConsole){ @"
				return Console.Title;
"@ } else {@"
				return System.AppDomain.CurrentDomain.FriendlyName;
"@ })
			}
			set
			{
$(if (!$noConsole){ @"
				Console.Title = value;
"@ })
			}
		}
	}

$(if ($noConsole){ @"
	public class InputBox
	{
		[DllImport("user32.dll", CharSet = CharSet.Unicode, CallingConvention = CallingConvention.Cdecl)]
		private static extern IntPtr MB_GetString(uint strId);

		public static DialogResult Show(string sTitle, string sPrompt, ref string sValue, bool bSecure)
		{
			Form form = new Form();
			Label label = new Label();
			TextBox textBox = new TextBox();
			Button buttonOk = new Button();
			Button buttonCancel = new Button();

			if (string.IsNullOrEmpty(sPrompt))
			{
				if (bSecure)
					label.Text = "Secure input:   ";
				else
					label.Text = "Input:          ";
			}
			else
				label.Text = sPrompt;
			label.Location = new Point(9, 19);
			label.AutoSize = true;
			form.Controls.Add(label);

			if (bSecure) textBox.UseSystemPasswordChar = true;
			textBox.Text = sValue;
			textBox.SetBounds(12, label.Bottom, label.Right - 12, 20);

			string sTextOK = Marshal.PtrToStringUni(MB_GetString(0));
			if (string.IsNullOrEmpty(sTextOK))
				buttonOk.Text = "OK";
			else
				buttonOk.Text = sTextOK;

			string sTextCancel = Marshal.PtrToStringUni(MB_GetString(1));
			if (string.IsNullOrEmpty(sTextCancel))
				buttonCancel.Text = "Cancel";
			else
				buttonCancel.Text = sTextCancel;

			buttonOk.DialogResult = DialogResult.OK;
			buttonCancel.DialogResult = DialogResult.Cancel;
			buttonOk.SetBounds(System.Math.Max(12, label.Right - 158), label.Bottom + 36, 75, 23);
			buttonCancel.SetBounds(System.Math.Max(93, label.Right - 77), label.Bottom + 36, 75, 23);

			if (string.IsNullOrEmpty(sTitle))
				form.Text = System.AppDomain.CurrentDomain.FriendlyName;
			else
				form.Text = sTitle;
			form.ClientSize = new System.Drawing.Size(System.Math.Max(178, label.Right + 10), label.Bottom + 71);
			form.Controls.AddRange(new Control[] { textBox, buttonOk, buttonCancel });
			form.FormBorderStyle = FormBorderStyle.FixedDialog;
			form.StartPosition = FormStartPosition.CenterScreen;
			form.MinimizeBox = false;
			form.MaximizeBox = false;
			form.AcceptButton = buttonOk;
			form.CancelButton = buttonCancel;

			DialogResult dialogResult = form.ShowDialog();
			sValue = textBox.Text;
			return dialogResult;
		}

		public static DialogResult Show(string sTitle, string sPrompt, ref string sValue)
		{
			return Show(sTitle, sPrompt, ref sValue, false);
		}
	}

	public class ChoiceBox
	{
		public static int Show(System.Collections.ObjectModel.Collection<ChoiceDescription> aAuswahl, int iVorgabe, string sTitle, string sPrompt)
		{
			if (aAuswahl == null) return -1;
			if (aAuswahl.Count < 1) return -1;

			Form form = new Form();
			RadioButton[] aradioButton = new RadioButton[aAuswahl.Count];
			ToolTip toolTip = new ToolTip();
			Button buttonOk = new Button();

			int iPosY = 19, iMaxX = 0;
			if (!string.IsNullOrEmpty(sPrompt))
			{
				Label label = new Label();
				label.Text = sPrompt;
				label.Location = new Point(9, 19);
				label.AutoSize = true;
				form.Controls.Add(label);
				iPosY = label.Bottom;
				iMaxX = label.Right;
			}

			int Counter = 0;
			foreach (ChoiceDescription sAuswahl in aAuswahl)
			{
				aradioButton[Counter] = new RadioButton();
				aradioButton[Counter].Text = sAuswahl.Label;
				if (Counter == iVorgabe)
				{ aradioButton[Counter].Checked = true; }
				aradioButton[Counter].Location = new Point(9, iPosY);
				aradioButton[Counter].AutoSize = true;
				form.Controls.Add(aradioButton[Counter]);
				iPosY = aradioButton[Counter].Bottom;
				if (aradioButton[Counter].Right > iMaxX) { iMaxX = aradioButton[Counter].Right; }
				if (!string.IsNullOrEmpty(sAuswahl.HelpMessage))
				{
					 toolTip.SetToolTip(aradioButton[Counter], sAuswahl.HelpMessage);
				}
				Counter++;
			}

			toolTip.ShowAlways = true;

			buttonOk.Text = "OK";
			buttonOk.DialogResult = DialogResult.OK;
			buttonOk.SetBounds(System.Math.Max(12, iMaxX - 77), iPosY + 36, 75, 23);

			if (string.IsNullOrEmpty(sTitle))
				form.Text = System.AppDomain.CurrentDomain.FriendlyName;
			else
				form.Text = sTitle;
			form.ClientSize = new System.Drawing.Size(System.Math.Max(178, iMaxX + 10), iPosY + 71);
			form.Controls.Add(buttonOk);
			form.FormBorderStyle = FormBorderStyle.FixedDialog;
			form.StartPosition = FormStartPosition.CenterScreen;
			form.MinimizeBox = false;
			form.MaximizeBox = false;
			form.AcceptButton = buttonOk;

			if (form.ShowDialog() == DialogResult.OK)
			{ int iRueck = -1;
				for (Counter = 0; Counter < aAuswahl.Count; Counter++)
				{
					if (aradioButton[Counter].Checked == true)
					{ iRueck = Counter; }
				}
				return iRueck;
			}
			else
				return -1;
		}
	}

	public class ReadKeyBox
	{
		[DllImport("user32.dll")]
		public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpKeyState,
			[Out, MarshalAs(UnmanagedType.LPWStr, SizeConst = 64)] System.Text.StringBuilder pwszBuff,
			int cchBuff, uint wFlags);

		static string GetCharFromKeys(Keys keys, bool bShift, bool bAltGr)
		{
			System.Text.StringBuilder buffer = new System.Text.StringBuilder(64);
			byte[] keyboardState = new byte[256];
			if (bShift)
			{ keyboardState[(int) Keys.ShiftKey] = 0xff; }
			if (bAltGr)
			{ keyboardState[(int) Keys.ControlKey] = 0xff;
				keyboardState[(int) Keys.Menu] = 0xff;
			}
			if (ToUnicode((uint) keys, 0, keyboardState, buffer, 64, 0) >= 1)
				return buffer.ToString();
			else
				return "\0";
		}

		class KeyboardForm : Form
		{
			public KeyboardForm()
			{
				this.KeyDown += new KeyEventHandler(KeyboardForm_KeyDown);
				this.KeyUp += new KeyEventHandler(KeyboardForm_KeyUp);
			}

			public bool checkKeyDown = true;
			public KeyInfo keyinfo;

			void KeyboardForm_KeyDown(object sender, KeyEventArgs e)
			{
				if (checkKeyDown)
				{
					keyinfo.VirtualKeyCode = e.KeyValue;
					keyinfo.Character = GetCharFromKeys(e.KeyCode, e.Shift, e.Alt & e.Control)[0];
					keyinfo.KeyDown = false;
					keyinfo.ControlKeyState = 0;
					if (e.Alt) { keyinfo.ControlKeyState = ControlKeyStates.LeftAltPressed | ControlKeyStates.RightAltPressed; }
					if (e.Control)
					{ keyinfo.ControlKeyState |= ControlKeyStates.LeftCtrlPressed | ControlKeyStates.RightCtrlPressed;
						if (!e.Alt)
						{ if (e.KeyValue > 64 && e.KeyValue < 96) keyinfo.Character = (char)(e.KeyValue - 64); }
					}
					if (e.Shift) { keyinfo.ControlKeyState |= ControlKeyStates.ShiftPressed; }
					if ((e.Modifiers & System.Windows.Forms.Keys.CapsLock) > 0) { keyinfo.ControlKeyState |= ControlKeyStates.CapsLockOn; }
					if ((e.Modifiers & System.Windows.Forms.Keys.NumLock) > 0) { keyinfo.ControlKeyState |= ControlKeyStates.NumLockOn; }
					this.Close();
				}
			}

			void KeyboardForm_KeyUp(object sender, KeyEventArgs e)
			{
				if (!checkKeyDown)
				{
					keyinfo.VirtualKeyCode = e.KeyValue;
					keyinfo.Character = GetCharFromKeys(e.KeyCode, e.Shift, e.Alt & e.Control)[0];
					keyinfo.KeyDown = true;
					keyinfo.ControlKeyState = 0;
					if (e.Alt) { keyinfo.ControlKeyState = ControlKeyStates.LeftAltPressed | ControlKeyStates.RightAltPressed; }
					if (e.Control)
					{ keyinfo.ControlKeyState |= ControlKeyStates.LeftCtrlPressed | ControlKeyStates.RightCtrlPressed;
						if (!e.Alt)
						{ if (e.KeyValue > 64 && e.KeyValue < 96) keyinfo.Character = (char)(e.KeyValue - 64); }
					}
					if (e.Shift) { keyinfo.ControlKeyState |= ControlKeyStates.ShiftPressed; }
					if ((e.Modifiers & System.Windows.Forms.Keys.CapsLock) > 0) { keyinfo.ControlKeyState |= ControlKeyStates.CapsLockOn; }
					if ((e.Modifiers & System.Windows.Forms.Keys.NumLock) > 0) { keyinfo.ControlKeyState |= ControlKeyStates.NumLockOn; }
					this.Close();
				}
			}
		}

		public static KeyInfo Show(string sTitle, string sPrompt, bool bIncludeKeyDown)
		{
			KeyboardForm form = new KeyboardForm();
			Label label = new Label();

			if (string.IsNullOrEmpty(sPrompt))
			{
					label.Text = "Press a key";
			}
			else
				label.Text = sPrompt;
			label.Location = new Point(9, 19);
			label.AutoSize = true;
			form.Controls.Add(label);

			if (string.IsNullOrEmpty(sTitle))
				form.Text = System.AppDomain.CurrentDomain.FriendlyName;
			else
				form.Text = sTitle;
			form.ClientSize = new System.Drawing.Size(System.Math.Max(178, label.Right + 10), label.Bottom + 55);
			form.FormBorderStyle = FormBorderStyle.FixedDialog;
			form.StartPosition = FormStartPosition.CenterScreen;
			form.MinimizeBox = false;
			form.MaximizeBox = false;

			form.checkKeyDown = bIncludeKeyDown;
			form.ShowDialog();
			return form.keyinfo;
		}
	}

	public class ProgressForm : Form
	{
		private Label objLblActivity;
		private Label objLblStatus;
		private ProgressBar objProgressBar;
		private Label objLblRemainingTime;
		private Label objLblOperation;
		private ConsoleColor ProgressBarColor = ConsoleColor.$ProgressBarColor;

		private Color DrawingColor(ConsoleColor color)
		{
			switch (color)
			{
				case ConsoleColor.Black: return Color.Black;
				case ConsoleColor.Blue: return Color.Blue;
				case ConsoleColor.Cyan: return Color.Cyan;
				case ConsoleColor.DarkBlue: return ColorTranslator.FromHtml("#000080");
				case ConsoleColor.DarkGray: return ColorTranslator.FromHtml("#808080");
				case ConsoleColor.DarkGreen: return ColorTranslator.FromHtml("#008000");
				case ConsoleColor.DarkCyan: return ColorTranslator.FromHtml("#008080");
				case ConsoleColor.DarkMagenta: return ColorTranslator.FromHtml("#800080");
				case ConsoleColor.DarkRed: return ColorTranslator.FromHtml("#800000");
				case ConsoleColor.DarkYellow: return ColorTranslator.FromHtml("#808000");
				case ConsoleColor.Gray: return ColorTranslator.FromHtml("#C0C0C0");
				case ConsoleColor.Green: return ColorTranslator.FromHtml("#00FF00");
				case ConsoleColor.Magenta: return Color.Magenta;
				case ConsoleColor.Red: return Color.Red;
				case ConsoleColor.White: return Color.White;
				default: return Color.Yellow;
			}
		}

		private void InitializeComponent()
		{
			this.SuspendLayout();

			this.Text = "Progress";
			this.Height = 160;
			this.Width = 800;
			this.BackColor = Color.White;
			this.FormBorderStyle = FormBorderStyle.FixedSingle;
			this.ControlBox = false;
			this.StartPosition = FormStartPosition.CenterScreen;

			objLblActivity = new Label();
			objLblActivity.Left = 5;
			objLblActivity.Top = 10;
			objLblActivity.Width = 800 - 20;
			objLblActivity.Height = 16;
			objLblActivity.Font = new Font(objLblActivity.Font, FontStyle.Bold);
			objLblActivity.Text = "";
			this.Controls.Add(objLblActivity);

			objLblStatus = new Label();
			objLblStatus.Left = 25;
			objLblStatus.Top = 26;
			objLblStatus.Width = 800 - 40;
			objLblStatus.Height = 16;
			objLblStatus.Text = "";
			this.Controls.Add(objLblStatus);

			objProgressBar = new ProgressBar();
			objProgressBar.Value = 0;
			objProgressBar.Style = ProgressBarStyle.Continuous;
			objProgressBar.ForeColor = DrawingColor(ProgressBarColor);
			objProgressBar.Size = new System.Drawing.Size(800 - 60, 20);
			objProgressBar.Left = 25;
			objProgressBar.Top = 55;
			this.Controls.Add(objProgressBar);

			objLblRemainingTime = new Label();
			objLblRemainingTime.Left = 5;
			objLblRemainingTime.Top = 85;
			objLblRemainingTime.Width = 800 - 20;
			objLblRemainingTime.Height = 16;
			objLblRemainingTime.Text = "";
			this.Controls.Add(objLblRemainingTime);

			objLblOperation = new Label();
			objLblOperation.Left = 25;
			objLblOperation.Top = 101;
			objLblOperation.Width = 800 - 40;
			objLblOperation.Height = 16;
			objLblOperation.Text = "";
			this.Controls.Add(objLblOperation);

			this.ResumeLayout();
		}

		public ProgressForm()
		{
			InitializeComponent();
		}

		public ProgressForm(ConsoleColor BarColor)
		{
			ProgressBarColor = BarColor;
			InitializeComponent();
		}

		public void Update(ProgressRecord objRecord)
		{
			if (objRecord == null)
				return;

			if (objRecord.RecordType == ProgressRecordType.Completed)
			{
				this.Close();
				return;
			}

			if (!string.IsNullOrEmpty(objRecord.Activity))
				objLblActivity.Text = objRecord.Activity;
			else
				objLblActivity.Text = "";

			if (!string.IsNullOrEmpty(objRecord.StatusDescription))
				objLblStatus.Text = objRecord.StatusDescription;
			else
				objLblStatus.Text = "";

			if ((objRecord.PercentComplete >= 0) && (objRecord.PercentComplete <= 100))
			{
				objProgressBar.Value = objRecord.PercentComplete;
				objProgressBar.Visible = true;
			}
			else
			{ if (objRecord.PercentComplete > 100)
				{
					objProgressBar.Value = 0;
					objProgressBar.Visible = true;
				}
				else
					objProgressBar.Visible = false;
			}

			if (objRecord.SecondsRemaining >= 0)
			{
				System.TimeSpan objTimeSpan = new System.TimeSpan(0, 0, objRecord.SecondsRemaining);
				objLblRemainingTime.Text = "Remaining time: " + string.Format("{0:00}:{1:00}:{2:00}", (int)objTimeSpan.TotalHours, objTimeSpan.Minutes, objTimeSpan.Seconds);
			}
			else
				objLblRemainingTime.Text = "";

			if (!string.IsNullOrEmpty(objRecord.CurrentOperation))
				objLblOperation.Text = objRecord.CurrentOperation;
			else
				objLblOperation.Text = "";

			this.Refresh();
			Application.DoEvents();
		}
	}
"@})

	public class ConsoleInfo
	{
		private enum FileType : uint
		{
			FILE_TYPE_UNKNOWN = 0x0000,
			FILE_TYPE_DISK = 0x0001,
			FILE_TYPE_CHAR = 0x0002,
			FILE_TYPE_PIPE = 0x0003,
			FILE_TYPE_REMOTE = 0x8000
		}

		private enum STDHandle : uint
		{
			STD_INPUT_HANDLE = unchecked((uint)-10),
			STD_OUTPUT_HANDLE = unchecked((uint)-11),
			STD_ERROR_HANDLE = unchecked((uint)-12)
		}

		[DllImport("Kernel32.dll")]
		static private extern UIntPtr GetStdHandle(STDHandle stdHandle);

		[DllImport("Kernel32.dll")]
		static private extern FileType GetFileType(UIntPtr hFile);

		static public bool IsInputRedirected()
		{
			UIntPtr hInput = GetStdHandle(STDHandle.STD_INPUT_HANDLE);
			FileType fileType = (FileType)GetFileType(hInput);
			if ((fileType == FileType.FILE_TYPE_CHAR) || (fileType == FileType.FILE_TYPE_UNKNOWN))
				return false;
			return true;
		}

		static public bool IsOutputRedirected()
		{
			UIntPtr hOutput = GetStdHandle(STDHandle.STD_OUTPUT_HANDLE);
			FileType fileType = (FileType)GetFileType(hOutput);
			if ((fileType == FileType.FILE_TYPE_CHAR) || (fileType == FileType.FILE_TYPE_UNKNOWN))
				return false;
			return true;
		}

		static public bool IsErrorRedirected()
		{
			UIntPtr hError = GetStdHandle(STDHandle.STD_ERROR_HANDLE);
			FileType fileType = (FileType)GetFileType(hError);
			if ((fileType == FileType.FILE_TYPE_CHAR) || (fileType == FileType.FILE_TYPE_UNKNOWN))
				return false;
			return true;
		}
	}


	internal class PS2EXEHostUI : PSHostUserInterface
	{
		private PS2EXEHostRawUI rawUI = null;

		public ConsoleColor ErrorForegroundColor = ConsoleColor.Red;
		public ConsoleColor ErrorBackgroundColor = ConsoleColor.Black;

		public ConsoleColor WarningForegroundColor = ConsoleColor.Yellow;
		public ConsoleColor WarningBackgroundColor = ConsoleColor.Black;

		public ConsoleColor DebugForegroundColor = ConsoleColor.Yellow;
		public ConsoleColor DebugBackgroundColor = ConsoleColor.Black;

		public ConsoleColor VerboseForegroundColor = ConsoleColor.Yellow;
		public ConsoleColor VerboseBackgroundColor = ConsoleColor.Black;

$(if (!$noConsole) {@"
		public ConsoleColor ProgressForegroundColor = ConsoleColor.Yellow;
"@ } else {@"
		public ConsoleColor ProgressForegroundColor = ConsoleColor.$ProgressBarColor;
"@ })
		public ConsoleColor ProgressBackgroundColor = ConsoleColor.$ProgressBarColor;

		public PS2EXEHostUI() : base()
		{
			rawUI = new PS2EXEHostRawUI();
$(if (!$noConsole) {@"
			rawUI.ForegroundColor = Console.ForegroundColor;
			rawUI.BackgroundColor = Console.BackgroundColor;
"@ })
		}

		public override Dictionary<string, PSObject> Prompt(string caption, string message, System.Collections.ObjectModel.Collection<FieldDescription> descriptions)
		{
$(if (!$noConsole) {@"
			if (!string.IsNullOrEmpty(caption)) WriteLine(caption);
			if (!string.IsNullOrEmpty(message)) WriteLine(message);
"@ } else {@"
			if ((!string.IsNullOrEmpty(caption)) || (!string.IsNullOrEmpty(message)))
			{ string sTitel = System.AppDomain.CurrentDomain.FriendlyName, sMeldung = "";

				if (!string.IsNullOrEmpty(caption)) sTitel = caption;
				if (!string.IsNullOrEmpty(message)) sMeldung = message;
				MessageBox.Show(sMeldung, sTitel);
			}

			ibcaption = "";
			ibmessage = "";
"@ })
			Dictionary<string, PSObject> ret = new Dictionary<string, PSObject>();
			foreach (FieldDescription cd in descriptions)
			{
				Type t = null;
				if (string.IsNullOrEmpty(cd.ParameterAssemblyFullName))
					t = typeof(string);
				else
					t = Type.GetType(cd.ParameterAssemblyFullName);

				if (t.IsArray)
				{
					Type elementType = t.GetElementType();
					Type genericListType = Type.GetType("System.Collections.Generic.List"+((char)0x60).ToString()+"1");
					genericListType = genericListType.MakeGenericType(new Type[] { elementType });
					ConstructorInfo constructor = genericListType.GetConstructor(BindingFlags.CreateInstance | BindingFlags.Instance | BindingFlags.Public, null, Type.EmptyTypes, null);
					object resultList = constructor.Invoke(null);

					int index = 0;
					string data = "";
					do
					{
						try
						{
$(if (!$noConsole) {@"
							if (!string.IsNullOrEmpty(cd.Name)) Write(string.Format("{0}[{1}]: ", cd.Name, index));
"@ } else {@"
							if (!string.IsNullOrEmpty(cd.Name)) ibmessage = string.Format("{0}[{1}]: ", cd.Name, index);
"@ })
							data = ReadLine();
							if (string.IsNullOrEmpty(data))
								break;

							object o = System.Convert.ChangeType(data, elementType);
							genericListType.InvokeMember("Add", BindingFlags.InvokeMethod | BindingFlags.Public | BindingFlags.Instance, null, resultList, new object[] { o });
						}
						catch (Exception e)
						{
							throw e;
						}
						index++;
					} while (true);

					System.Array retArray = (System.Array )genericListType.InvokeMember("ToArray", BindingFlags.InvokeMethod | BindingFlags.Public | BindingFlags.Instance, null, resultList, null);
					ret.Add(cd.Name, new PSObject(retArray));
				}
				else
				{
					object o = null;
					string l = null;
					try
					{
						if (t != typeof(System.Security.SecureString))
						{
							if (t != typeof(System.Management.Automation.PSCredential))
							{
$(if (!$noConsole) {@"
								if (!string.IsNullOrEmpty(cd.Name)) Write(cd.Name);
								if (!string.IsNullOrEmpty(cd.HelpMessage)) Write(" (Type !? for help.)");
								if ((!string.IsNullOrEmpty(cd.Name)) || (!string.IsNullOrEmpty(cd.HelpMessage))) Write(": ");
"@ } else {@"
								if (!string.IsNullOrEmpty(cd.Name)) ibmessage = string.Format("{0}: ", cd.Name);
								if (!string.IsNullOrEmpty(cd.HelpMessage)) ibmessage += "\n(Type !? for help.)";
"@ })
								do {
									l = ReadLine();
									if (l == "!?")
										WriteLine(cd.HelpMessage);
									else
									{
										if (string.IsNullOrEmpty(l)) o = cd.DefaultValue;
										if (o == null)
										{
											try {
												o = System.Convert.ChangeType(l, t);
											}
											catch {
												Write("Wrong format, please repeat input: ");
												l = "!?";
											}
										}
									}
								} while (l == "!?");
							}
							else
							{
								PSCredential pscred = PromptForCredential("", "", "", "");
								o = pscred;
							}
						}
						else
						{
$(if (!$noConsole) {@"
								if (!string.IsNullOrEmpty(cd.Name)) Write(string.Format("{0}: ", cd.Name));
"@ } else {@"
								if (!string.IsNullOrEmpty(cd.Name)) ibmessage = string.Format("{0}: ", cd.Name);
"@ })

							SecureString pwd = null;
							pwd = ReadLineAsSecureString();
							o = pwd;
						}

						ret.Add(cd.Name, new PSObject(o));
					}
					catch (Exception e)
					{
						throw e;
					}
				}
			}
$(if ($noConsole) {@"
			ibcaption = "";
			ibmessage = "";
"@ })
			return ret;
		}

		public override int PromptForChoice(string caption, string message, System.Collections.ObjectModel.Collection<ChoiceDescription> choices, int defaultChoice)
		{
$(if ($noConsole) {@"
			int iReturn = ChoiceBox.Show(choices, defaultChoice, caption, message);
			if (iReturn == -1) { iReturn = defaultChoice; }
			return iReturn;
"@ } else {@"
			if (!string.IsNullOrEmpty(caption))
				WriteLine(caption);
			WriteLine(message);
			int idx = 0;
			SortedList<string, int> res = new SortedList<string, int>();
			foreach (ChoiceDescription cd in choices)
			{
				string lkey = cd.Label.Substring(0, 1), ltext = cd.Label;
				int pos = cd.Label.IndexOf('&');
				if (pos > -1)
				{
					lkey = cd.Label.Substring(pos + 1, 1).ToUpper();
					if (pos > 0)
						ltext = cd.Label.Substring(0, pos) + cd.Label.Substring(pos + 1);
					else
						ltext = cd.Label.Substring(1);
				}
				res.Add(lkey.ToLower(), idx);

				if (idx > 0) Write("  ");
				if (idx == defaultChoice)
				{
					Write(ConsoleColor.Yellow, Console.BackgroundColor, string.Format("[{0}] {1}", lkey, ltext));
					if (!string.IsNullOrEmpty(cd.HelpMessage))
						Write(ConsoleColor.Gray, Console.BackgroundColor, string.Format(" ({0})", cd.HelpMessage));
				}
				else
				{
					Write(ConsoleColor.Gray, Console.BackgroundColor, string.Format("[{0}] {1}", lkey, ltext));
					if (!string.IsNullOrEmpty(cd.HelpMessage))
						Write(ConsoleColor.Gray, Console.BackgroundColor, string.Format(" ({0})", cd.HelpMessage));
				}
				idx++;
			}
			Write(": ");

			try
			{
				while (true)
				{ string s = Console.ReadLine().ToLower();
					if (res.ContainsKey(s))
						return res[s];
					if (string.IsNullOrEmpty(s))
						return defaultChoice;
				}
			}
			catch { }

			return defaultChoice;
"@ })
		}

		public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
		{
$(if (!$noConsole -and !$credentialGUI) {@"
			if (!string.IsNullOrEmpty(caption)) WriteLine(caption);
			WriteLine(message);

			string un;
			if ((string.IsNullOrEmpty(userName)) || ((options & PSCredentialUIOptions.ReadOnlyUserName) == 0))
			{
				Write("User name: ");
				un = ReadLine();
			}
			else
			{
				Write("User name: ");
				if (!string.IsNullOrEmpty(targetName)) Write(targetName + "\\");
				WriteLine(userName);
				un = userName;
			}
			SecureString pwd = null;
			Write("Password: ");
			pwd = ReadLineAsSecureString();

			if (string.IsNullOrEmpty(un)) un = "<NOUSER>";
			if (!string.IsNullOrEmpty(targetName))
			{
				if (un.IndexOf('\\') < 0)
					un = targetName + "\\" + un;
			}

			PSCredential c2 = new PSCredential(un, pwd);
			return c2;
"@ } else {@"
			ik.PowerShell.CredentialForm.UserPwd cred = CredentialForm.PromptForPassword(caption, message, targetName, userName, allowedCredentialTypes, options);
			if (cred != null)
			{
				System.Security.SecureString x = new System.Security.SecureString();
				foreach (char c in cred.Password.ToCharArray())
					x.AppendChar(c);

				return new PSCredential(cred.User, x);
			}
			return null;
"@ })
		}

		public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
		{
$(if (!$noConsole -and !$credentialGUI) {@"
			if (!string.IsNullOrEmpty(caption)) WriteLine(caption);
			WriteLine(message);

			string un;
			if (string.IsNullOrEmpty(userName))
			{
				Write("User name: ");
				un = ReadLine();
			}
			else
			{
				Write("User name: ");
				if (!string.IsNullOrEmpty(targetName)) Write(targetName + "\\");
				WriteLine(userName);
				un = userName;
			}
			SecureString pwd = null;
			Write("Password: ");
			pwd = ReadLineAsSecureString();

			if (string.IsNullOrEmpty(un)) un = "<NOUSER>";
			if (!string.IsNullOrEmpty(targetName))
			{
				if (un.IndexOf('\\') < 0)
					un = targetName + "\\" + un;
			}

			PSCredential c2 = new PSCredential(un, pwd);
			return c2;
"@ } else {@"
			ik.PowerShell.CredentialForm.UserPwd cred = CredentialForm.PromptForPassword(caption, message, targetName, userName, PSCredentialTypes.Default, PSCredentialUIOptions.Default);
			if (cred != null)
			{
				System.Security.SecureString x = new System.Security.SecureString();
				foreach (char c in cred.Password.ToCharArray())
					x.AppendChar(c);

				return new PSCredential(cred.User, x);
			}
			return null;
"@ })
		}

		public override PSHostRawUserInterface RawUI
		{
			get
			{
				return rawUI;
			}
		}

$(if ($noConsole) {@"
		private string ibcaption;
		private string ibmessage;
"@ })

		public override string ReadLine()
		{
$(if (!$noConsole) {@"
			return Console.ReadLine();
"@ } else {@"
			string sWert = "";
			if (InputBox.Show(ibcaption, ibmessage, ref sWert) == DialogResult.OK)
				return sWert;
			else
				return "";
"@ })
		}

		private System.Security.SecureString getPassword()
		{
			System.Security.SecureString pwd = new System.Security.SecureString();
			while (true)
			{
				ConsoleKeyInfo i = Console.ReadKey(true);
				if (i.Key == ConsoleKey.Enter)
				{
					Console.WriteLine();
					break;
				}
				else if (i.Key == ConsoleKey.Backspace)
				{
					if (pwd.Length > 0)
					{
						pwd.RemoveAt(pwd.Length - 1);
						Console.Write("\b \b");
					}
				}
				else
				{
					pwd.AppendChar(i.KeyChar);
					Console.Write("*");
				}
			}
			return pwd;
		}

		public override System.Security.SecureString ReadLineAsSecureString()
		{
			System.Security.SecureString secstr = new System.Security.SecureString();
$(if (!$noConsole) {@"
			secstr = getPassword();
"@ } else {@"
			string sWert = "";

			if (InputBox.Show(ibcaption, ibmessage, ref sWert, true) == DialogResult.OK)
			{
				foreach (char ch in sWert)
					secstr.AppendChar(ch);
			}
"@ })
			return secstr;
		}

		public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
		{
$(if (!$noConsole) {@"
			ConsoleColor fgc = Console.ForegroundColor, bgc = Console.BackgroundColor;
			Console.ForegroundColor = foregroundColor;
			Console.BackgroundColor = backgroundColor;
			Console.Write(value);
			Console.ForegroundColor = fgc;
			Console.BackgroundColor = bgc;
"@ } else {@"
			if ((!string.IsNullOrEmpty(value)) && (value != "\n"))
				MessageBox.Show(value, System.AppDomain.CurrentDomain.FriendlyName);
"@ })
		}

		public override void Write(string value)
		{
$(if (!$noConsole) {@"
			Console.Write(value);
"@ } else {@"
			if ((!string.IsNullOrEmpty(value)) && (value != "\n"))
				MessageBox.Show(value, System.AppDomain.CurrentDomain.FriendlyName);
"@ })
		}

		public override void WriteDebugLine(string message)
		{
$(if (!$noConsole) {@"
			WriteLine(DebugForegroundColor, DebugBackgroundColor, string.Format("DEBUG: {0}", message));
"@ } else {@"
			MessageBox.Show(message, System.AppDomain.CurrentDomain.FriendlyName, MessageBoxButtons.OK, MessageBoxIcon.Information);
"@ })
		}

		public override void WriteErrorLine(string value)
		{
$(if (!$noConsole) {@"
			if (ConsoleInfo.IsErrorRedirected())
				Console.Error.WriteLine(string.Format("ERROR: {0}", value));
			else
				WriteLine(ErrorForegroundColor, ErrorBackgroundColor, string.Format("ERROR: {0}", value));
"@ } else {@"
			MessageBox.Show(value, System.AppDomain.CurrentDomain.FriendlyName, MessageBoxButtons.OK, MessageBoxIcon.Error);
"@ })
		}

		public override void WriteLine()
		{
$(if (!$noConsole) {@"
			Console.WriteLine();
"@ } else {@"
			MessageBox.Show("", System.AppDomain.CurrentDomain.FriendlyName);
"@ })
		}

		public override void WriteLine(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
		{
$(if (!$noConsole) {@"
			ConsoleColor fgc = Console.ForegroundColor, bgc = Console.BackgroundColor;
			Console.ForegroundColor = foregroundColor;
			Console.BackgroundColor = backgroundColor;
			Console.WriteLine(value);
			Console.ForegroundColor = fgc;
			Console.BackgroundColor = bgc;
"@ } else {@"
			if ((!string.IsNullOrEmpty(value)) && (value != "\n"))
				MessageBox.Show(value, System.AppDomain.CurrentDomain.FriendlyName);
"@ })
		}

		public override void WriteLine(string value)
		{
$(if (!$noConsole) {@"
			Console.WriteLine(value);
"@ } else {@"
			if ((!string.IsNullOrEmpty(value)) && (value != "\n"))
				MessageBox.Show(value, System.AppDomain.CurrentDomain.FriendlyName);
"@ })
		}

$(if ($noConsole) {@"
		public ProgressForm pf = null;
"@ })
		public override void WriteProgress(long sourceId, ProgressRecord record)
		{
$(if ($noConsole) {@"
			if (pf == null)
			{
				pf = new ProgressForm(ProgressForegroundColor);
				pf.Show();
			}
			pf.Update(record);
			if (record.RecordType == ProgressRecordType.Completed)
			{
				pf = null;
			}
"@ })
		}

		public override void WriteVerboseLine(string message)
		{
$(if (!$noConsole) {@"
			WriteLine(VerboseForegroundColor, VerboseBackgroundColor, string.Format("VERBOSE: {0}", message));
"@ } else {@"
			MessageBox.Show(message, System.AppDomain.CurrentDomain.FriendlyName, MessageBoxButtons.OK, MessageBoxIcon.Information);
"@ })
		}

		public override void WriteWarningLine(string message)
		{
$(if (!$noConsole) {@"
			WriteLine(WarningForegroundColor, WarningBackgroundColor, string.Format("WARNING: {0}", message));
"@ } else {@"
			MessageBox.Show(message, System.AppDomain.CurrentDomain.FriendlyName, MessageBoxButtons.OK, MessageBoxIcon.Warning);
"@ })
		}
	}

	internal class PS2EXEHost : PSHost
	{
		private PS2EXEApp parent;
		private PS2EXEHostUI ui = null;

		private CultureInfo originalCultureInfo = System.Threading.Thread.CurrentThread.CurrentCulture;

		private CultureInfo originalUICultureInfo = System.Threading.Thread.CurrentThread.CurrentUICulture;

		private Guid myId = Guid.NewGuid();

		public PS2EXEHost(PS2EXEApp app, PS2EXEHostUI ui)
		{
			this.parent = app;
			this.ui = ui;
		}

		public class ConsoleColorProxy
		{
			private PS2EXEHostUI _ui;

			public ConsoleColorProxy(PS2EXEHostUI ui)
			{
				if (ui == null) throw new ArgumentNullException("ui");
				_ui = ui;
			}

			public ConsoleColor ErrorForegroundColor
			{
				get
				{ return _ui.ErrorForegroundColor; }
				set
				{ _ui.ErrorForegroundColor = value; }
			}

			public ConsoleColor ErrorBackgroundColor
			{
				get
				{ return _ui.ErrorBackgroundColor; }
				set
				{ _ui.ErrorBackgroundColor = value; }
			}

			public ConsoleColor WarningForegroundColor
			{
				get
				{ return _ui.WarningForegroundColor; }
				set
				{ _ui.WarningForegroundColor = value; }
			}

			public ConsoleColor WarningBackgroundColor
			{
				get
				{ return _ui.WarningBackgroundColor; }
				set
				{ _ui.WarningBackgroundColor = value; }
			}

			public ConsoleColor DebugForegroundColor
			{
				get
				{ return _ui.DebugForegroundColor; }
				set
				{ _ui.DebugForegroundColor = value; }
			}

			public ConsoleColor DebugBackgroundColor
			{
				get
				{ return _ui.DebugBackgroundColor; }
				set
				{ _ui.DebugBackgroundColor = value; }
			}

			public ConsoleColor VerboseForegroundColor
			{
				get
				{ return _ui.VerboseForegroundColor; }
				set
				{ _ui.VerboseForegroundColor = value; }
			}

			public ConsoleColor VerboseBackgroundColor
			{
				get
				{ return _ui.VerboseBackgroundColor; }
				set
				{ _ui.VerboseBackgroundColor = value; }
			}

			public ConsoleColor ProgressForegroundColor
			{
				get
				{ return _ui.ProgressForegroundColor; }
				set
				{ _ui.ProgressForegroundColor = value; }
			}

			public ConsoleColor ProgressBackgroundColor
			{
				get
				{ return _ui.ProgressBackgroundColor; }
				set
				{ _ui.ProgressBackgroundColor = value; }
			}
		}

		public override PSObject PrivateData
		{
			get
			{
				if (ui == null) return null;
				return _consoleColorProxy ?? (_consoleColorProxy = PSObject.AsPSObject(new ConsoleColorProxy(ui)));
			}
		}

		private PSObject _consoleColorProxy;

		public override System.Globalization.CultureInfo CurrentCulture
		{
			get
			{
				return this.originalCultureInfo;
			}
		}

		public override System.Globalization.CultureInfo CurrentUICulture
		{
			get
			{
				return this.originalUICultureInfo;
			}
		}

		public override Guid InstanceId
		{
			get
			{
				return this.myId;
			}
		}

		public override string Name
		{
			get
			{
				return "PS2EXE_Host";
			}
		}

		public override PSHostUserInterface UI
		{
			get
			{
				return ui;
			}
		}

		public override Version Version
		{
			get
			{
				return new Version(0, 5, 0, 14);
			}
		}

		public override void EnterNestedPrompt()
		{
		}

		public override void ExitNestedPrompt()
		{
		}

		public override void NotifyBeginApplication()
		{
			return;
		}

		public override void NotifyEndApplication()
		{
			return;
		}

		public override void SetShouldExit(int exitCode)
		{
			this.parent.ShouldExit = true;
			this.parent.ExitCode = exitCode;
		}
	}

	internal interface PS2EXEApp
	{
		bool ShouldExit { get; set; }
		int ExitCode { get; set; }
	}

	internal class PS2EXE : PS2EXEApp
	{
		private bool shouldExit;

		private int exitCode;

		public bool ShouldExit
		{
			get { return this.shouldExit; }
			set { this.shouldExit = value; }
		}

		public int ExitCode
		{
			get { return this.exitCode; }
			set { this.exitCode = value; }
		}

		$(if ($Sta){"[STAThread]"})$(if ($Mta){"[MTAThread]"})
		private static int Main(string[] args)
		{
			$culture

			PS2EXE me = new PS2EXE();

			bool paramWait = false;
			string extractFN = string.Empty;

			PS2EXEHostUI ui = new PS2EXEHostUI();
			PS2EXEHost host = new PS2EXEHost(me, ui);
			System.Threading.ManualResetEvent mre = new System.Threading.ManualResetEvent(false);

			AppDomain.CurrentDomain.UnhandledException += new UnhandledExceptionEventHandler(CurrentDomain_UnhandledException);

			try
			{
				using (Runspace myRunSpace = RunspaceFactory.CreateRunspace(host))
				{
					$(if ($Sta -or $Mta) {"myRunSpace.ApartmentState = System.Threading.ApartmentState."})$(if ($Sta){"STA"})$(if ($Mta){"MTA"});
					myRunSpace.Open();

					using (System.Management.Automation.PowerShell powershell = System.Management.Automation.PowerShell.Create())
					{
$(if (!$noConsole) {@"
						Console.CancelKeyPress += new ConsoleCancelEventHandler(delegate(object sender, ConsoleCancelEventArgs e)
						{
							try
							{
								powershell.BeginStop(new AsyncCallback(delegate(IAsyncResult r)
								{
									mre.Set();
									e.Cancel = true;
								}), null);
							}
							catch
							{
							};
						});
"@ })

						powershell.Runspace = myRunSpace;
						powershell.Streams.Error.DataAdded += new EventHandler<DataAddedEventArgs>(delegate(object sender, DataAddedEventArgs e)
						{
							ui.WriteErrorLine(((PSDataCollection<ErrorRecord>)sender)[e.Index].ToString());
						});

						PSDataCollection<string> colInput = new PSDataCollection<string>();
$(if (!$runtime20) {@"
						if (ConsoleInfo.IsInputRedirected())
						{
							string sItem = "";
							while ((sItem = Console.ReadLine()) != null)
							{
								colInput.Add(sItem);
							}
						}
"@ })
						colInput.Complete();

						PSDataCollection<PSObject> colOutput = new PSDataCollection<PSObject>();
						colOutput.DataAdded += new EventHandler<DataAddedEventArgs>(delegate(object sender, DataAddedEventArgs e)
						{
							ui.WriteLine(colOutput[e.Index].ToString());
						});

						int separator = 0;
						int idx = 0;
						foreach (string s in args)
						{
							if (string.Compare(s, "-wait", true) == 0)
								paramWait = true;
							$ExtractString
							else if (string.Compare(s, "-end", true) == 0)
							{
								separator = idx + 1;
								break;
							}
							else if (string.Compare(s, "-debug", true) == 0)
							{
								System.Diagnostics.Debugger.Launch();
								break;
							}
							idx++;
						}

						string script = System.Text.Encoding.UTF8.GetString(System.Convert.FromBase64String(@"$($script)"));

						if (!string.IsNullOrEmpty(extractFN))
						{
							System.IO.File.WriteAllText(extractFN, script);
							return 0;
						}

						powershell.AddScript(script);

						string argbuffer = null;
						System.Text.RegularExpressions.Regex regex = new System.Text.RegularExpressions.Regex(@"^-([^: ]+)[ :]?([^:]*)$");

						for (int i = separator; i < args.Length; i++)
						{
							System.Text.RegularExpressions.Match match = regex.Match(args[i]);
							if (match.Success && match.Groups.Count == 3)
							{
								if (argbuffer != null)
									powershell.AddParameter(argbuffer);

								if (match.Groups[2].Value.Trim() == "")
								{
									argbuffer = match.Groups[1].Value;
								}
								else
									if ((match.Groups[2].Value == "$TRUE") || (match.Groups[2].Value.ToUpper() == "\x24TRUE"))
									{
										powershell.AddParameter(match.Groups[1].Value, true);
										argbuffer = null;
									}
									else
										if ((match.Groups[2].Value == "$FALSE") || (match.Groups[2].Value.ToUpper() == "\x24"+"FALSE"))
										{
											powershell.AddParameter(match.Groups[1].Value, false);
											argbuffer = null;
										}
										else
										{
											powershell.AddParameter(match.Groups[1].Value, match.Groups[2].Value);
											argbuffer = null;
										}
							}
							else
							{
								if (argbuffer != null)
								{
									powershell.AddParameter(argbuffer, args[i]);
									argbuffer = null;
								}
								else
								{
									powershell.AddArgument(args[i]);
								}
							}
						}

						if (argbuffer != null) powershell.AddParameter(argbuffer); // flush parameter buffer...

						powershell.AddCommand("out-string");
						powershell.AddParameter("stream");

						powershell.BeginInvoke<string, PSObject>(colInput, colOutput, null, new AsyncCallback(delegate(IAsyncResult ar)
						{
							if (ar.IsCompleted)
								mre.Set();
						}), null);

						while (!me.ShouldExit && !mre.WaitOne(100))
						{ };

						powershell.Stop();

						if (powershell.InvocationStateInfo.State == PSInvocationState.Failed)
							ui.WriteErrorLine(powershell.InvocationStateInfo.Reason.Message);
					}

					myRunSpace.Close();
				}
			}
			catch (Exception ex)
			{
$(if (!$noConsole) {@"
				Console.Write("An exception occured: ");
				Console.WriteLine(ex.Message);
"@ } else {@"
				MessageBox.Show("An exception occured: " + ex.Message, System.AppDomain.CurrentDomain.FriendlyName, MessageBoxButtons.OK, MessageBoxIcon.Error);
"@ })
			}

			if (paramWait)
			{
$(if (!$noConsole) {@"
				Console.WriteLine("Hit any key to exit...");
				Console.ReadKey();
"@ } else {@"
				MessageBox.Show("Click OK to exit...", System.AppDomain.CurrentDomain.FriendlyName);
"@ })
			}
			return me.ExitCode;
		}

		static void CurrentDomain_UnhandledException(object sender, UnhandledExceptionEventArgs e)
		{
			throw new Exception("Unhandled exception in PS2EXE");
		}
	}
}
"@
#endregion

$configFileForEXE3 = "<?xml version=""1.0"" encoding=""utf-8"" ?>`r`n<configuration><startup><supportedRuntime version=""v4.0"" sku="".NETFramework,Version=v4.0"" /></startup></configuration>"

if ($longPaths){$configFileForEXE3 = "<?xml version=""1.0"" encoding=""utf-8"" ?>`r`n<configuration><startup><supportedRuntime version=""v4.0"" sku="".NETFramework,Version=v4.0"" /></startup><runtime><AppContextSwitchOverrides value=""Switch.System.IO.UseLegacyPathHandling=false;Switch.System.IO.BlockLongPaths=false"" /></runtime></configuration>"}

$cr = $cop.CompileAssemblyFromSource($cp, $programFrame)
if ($cr.Errors.Count -gt 0){
	if (Test-Path $outputFile){Remove-Item $outputFile -Verbose:$FALSE}
	IF (!($VerboseBuild)){Stop-Error -Message "Could not create the PowerShell .exe file because of compilation errors. Use -VerboseBuild parameter to see details." -ExitCode 1}
	$cr.Errors | ForEach-Object { Write-Error $_ -Verbose:$VerboseBuild}
} else {
	if (Test-Path $outputFile){
		if ($DebugBuild){
			$cr.TempFiles | Where-Object { $_ -ilike "*.cs" } | Select-Object -first 1 | ForEach-Object {
				$dstSrc = ([System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($outputFile), [System.IO.Path]::GetFileNameWithoutExtension($outputFile)+".cs"))
				Copy-Item -Path $_ -Destination $dstSrc -Force
			}
			$cr.TempFiles | Remove-Item -Verbose:$FALSE -Force -ErrorAction SilentlyContinue
		}
		if (!$noConfigfile){if ($runtime40){$configFileForEXE3 | Set-Content ($outputFile+".config") -Encoding UTF8}}
	} else {Stop-Error -Message "$outputFile was not created" -ExitCode 1}
}

if ($requireAdmin -or $longPaths){ if (Test-Path $($outputFile+".win32manifest")){Remove-Item $($outputFile+".win32manifest") -Verbose:$FALSE}}
}

function Convert-FileToBase64 {
<#
.SYNOPSIS
Convert a file to base64 code
.DESCRIPTION
You can convert any file to base64 that can later be called by a script or embedded in a script
.PARAMETER InFile
Path to the file that is to be converted
.PARAMETER OutFile
Path to the output file
.PARAMETER BufferSize
Size of each chunck to be convered, should be a multiple of 3
.NOTES
Contact: Contact@mosacimk.com
Version 2.0.0
Original version: https://mnaoumov.wordpress.com/2013/08/20/efficient-base64-conversion-in-powershell/

How To use the base64 code
$BaseCode = @" <CodeFromTextFile> "@
Set-Content -Path "<NameOfFile>" -Value $BaseCode -Encoding Byte
or for large files use the Convert-FileFromBase64 function

.LINK
https://www.mosaicmk.com
#>
PARAM(
	[Parameter(Mandatory=$true)]
	[string]$InFile,
	[Parameter(Mandatory=$true)]
	[string]$OutFile,
	[int]$BufferSize = 9000
)
try {
	$InFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InFile)
	$OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
	# should be a multiplier of 3
	$buffer = New-Object byte[] $bufferSize
	$reader = [System.IO.File]::OpenRead($InFile)
	$writer = [System.IO.File]::CreateText($OutFile)
	$bytesRead = 0
	do{
		$bytesRead = $reader.Read($buffer, 0, $bufferSize);
		$writer.Write([Convert]::ToBase64String($buffer, 0, $bytesRead));
	} while ($bytesRead -eq $bufferSize);
	$reader.Dispose()
	$writer.Dispose()
}
catch {Write-Error "$_"}
}

function Convert-FileToDll {
<#
.SYNOPSIS
Convert a ps1 file to a encrypted file
.DESCRIPTION
Convert a PowerShell script file to a encryped file using 256bit AES encryption
To Use the dll in a script:
$Path = <Path to DLL>
$secure = Get-Content $path | ConvertTo-SecureString -Key (<Content of key file seperated by a ",">)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
$script = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
Invoke-Expression $script
.PARAMETER InFile
Path to the PowerShell script
.PARAMETER OutFile
Path to wheer the encrypted file is to be placed file
.PARAMETER KeyToFile
Path to where the key is to be written
.PARAMETER KeyToHost
Writes the key to the host window
.PARAMETER KeyFile
Path to a pre created file containing the key you wish to use (Can be created with New-AESKeyFile)
.EXAMPLE
PS2DLL.ps1 -InFile C:\Read-File.ps1 -OutFile C:\Read-File.dll -KeyToFile
This will enctypt Read-File.ps1 to read-file.dll and print the key
.NOTES
Contact: Contact@mosaicMK.com
Version 1.1.2
.LINK
https://www.mosaicmk.com
#>
	PARAM
	(
		[Parameter(Mandatory=$true)]
		[string]$InFile,
		[Parameter(Mandatory=$true,HelpMessage="Must be a DLL file")]
		[ValidateScript({$_ -like "*.dll"})]
		[string]$OutFile,
		[switch]$KeyToFile,
		[switch]$KeyToHost,
		[string]$KeyFile
	)
	try {
		IF (!($KeyFile)){[byte[]]$Key = (0..100) + (100..200)| Get-Random -Count 32 -ErrorAction Stop} else {[byte[]]$Key = Get-Content "$KeyFile" -ErrorAction Stop}
		$script = Get-Content $InFile -ErrorAction Stop | Out-String
		$secure = ConvertTo-SecureString $script -asPlainText -force -ErrorAction Stop
		$export = $secure | ConvertFrom-SecureString -Key $key -ErrorAction Stop
		Set-Content $OutFile $export -ErrorAction Stop
		IF (!($KeyFile)){
			IF ($KeyToFile){
				$KeyFile =  $OutFile -replace ".dll",".txt"
				Set-Content $KeyFile $Key
			}
			If ($KeyToHost -or !($KeyToFile)){
				[string]$outKey = $key -join ","
				Write-Host "Your Key: $outkey"
			}
		}
	}
	catch {Write-Error "$_"}
}

function New-AESKeyFile {
<#
.SYNOPSIS
Create a file containing a 256 bit key
.DESCRIPTION
Creates a file that can be used with Convert-FileToDll
.PARAMETER KeyFile
Path to where the Key file is to be created
.EXAMPLE
New-AESKeyFile -KeyFile C:\File.txt
Creates the file at C:\File.txt
.NOTES
Contact: Contact@mosaicMK.com
Version 1.0.0
.LINK
https://www.Mosaicmk.com/
#>
	param ([Parameter(Mandatory=$true)][string]$KeyFile)
	try {
		[byte[]]$KeyGen = (0..100) + (100..200) | Get-Random -Count 32 -ErrorAction Stop
		Set-Content -Value $KeyGen -Path "$KeyFile" -ErrorAction Stop
	}
	catch {Write-Error "$_"}
}

function Convert-StringToSecureString {
<#
.SYNOPSIS
Convert string to a secure string
.DESCRIPTION
Convert a strign to a 256 bit ecrypet string to be used in a script
.PARAMETER InString
The string to be encrypted
.PARAMETER SecureStringToFile
Writes the secure stringto a file
.PARAMETER SecureStringToHost
Writes the string to the host window
.PARAMETER KeyToFile
Writes the decryption key to a file
.PARAMETER KeyToHost
Writes the decryption key to the host window
.EXAMPLE
Convert-StringToSecureString -InString "John Smith lives at 8888 Park Drive" -SecureStringToHost -KeyToHost
Encrypts the string "John Smith lives at 8888 Park Drive" and Write they encrypted string to the host and the
key used to encrypt the string.
.NOTES
Contact: Contact@mosaicmk.com
Version 1.1.1
.LINK
http://www.mosaicmk.com/
#>
PARAM(
	[Parameter(Mandatory=$true)]
	[string]$InString,
	[string]$SecureStringToFile,
	[switch]$SecureStringToHost,
	[string]$KeyToFile,
	[switch]$KeyToHost,
	[string]$KeyFile
)

	IF (!($KeyFile)){[byte[]]$Key = (0..100) + (100..200)| Get-Random -Count 32 -ErrorAction Stop} else {[byte[]]$Key = Get-Content "$KeyFile" -ErrorAction Stop}
	$secure = ConvertTo-SecureString $InString -asPlainText -force
	$export = $secure | ConvertFrom-SecureString -Key $key
	If ($SecureStringToFile){Set-Content $SecureStringToFile $export}
	If ($SecureStringToHost){Write-Host "SecureString: $export"}
	IF ($KeyToFile){Set-Content $KeyToFile $Key}
	IF ($KeyToHost){Write-Host "Key: $Key"}
}

function Read-AESKeyFile {
<#
.SYNOPSIS
Read a AES key
.DESCRIPTION
Prints the AES key from a file to the host window allow the key to be pasted into a script or command
.PARAMETER KeyFile
Path to where the Key file is
.NOTES
Contact: Contact@mosaicMK.com
Version 1.0.0
.LINK
https://www.mosaicmk.com/
#>
param ([Parameter(Mandatory=$true)][string]$KeyFile)
	try {
		$Rkey = Get-Content "$KeyFile" -ErrorAction Stop
		$RKey = $Rkey -join ","
		$KeyObject = New-Object -TypeName psobject
		$KeyObject | Add-Member -MemberType NoteProperty -Name Key -Value $Rkey
		$KeyObject
	} Catch {Write-Error "$_"}
}

function Convert-FileFromBase64{
<#
.SYNOPSIS
Convert a file from base64 code
.DESCRIPTION
Converts a file stored as BASE64 code back to its Original form
.PARAMETER InFile
Path to the file that is to be converted from
.PARAMETER OutFile
Path to the output file
.PARAMETER BufferSize
Size of each chunck to be convered, should be a multiple of 3
.NOTES
Contact: Contact@mosacimk.com
Version 1.0.0
Original version: https://mnaoumov.wordpress.com/2013/08/20/efficient-base64-conversion-in-powershell/
.LINK
https://www.mosaicmk.com
#>

PARAM(
	[Parameter(Mandatory=$true)]
	[string]$InFile,
	[Parameter(Mandatory=$true)]
	[string]$OutFile,
	[int]$BufferSize = 9000
)
try {
	$InFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InFile)
	$OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
	$buffer = New-Object char[] $bufferSize
	$reader = [System.IO.File]::OpenText($InFile)
	$writer = [System.IO.File]::OpenWrite($OutFile)
	$bytesRead = 0
	do{
		$bytesRead = $reader.Read($buffer, 0, $bufferSize);
		$bytes = [Convert]::FromBase64CharArray($buffer, 0, $bytesRead);
		$writer.Write($bytes, 0, $bytes.Length);
	} while ($bytesRead -eq $bufferSize);
	$reader.Dispose()
	$writer.Dispose()
} catch {Write-Error "$_"}
}
