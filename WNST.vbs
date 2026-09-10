Option Explicit
Dim shell, fso, scriptPath, powershellPath, arguments
Set shell = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "Start-WNST.ps1")
powershellPath = fso.BuildPath(CreateObject("WScript.Shell").ExpandEnvironmentStrings("%SystemRoot%"), "System32\WindowsPowerShell\v1.0\powershell.exe")
arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & scriptPath & """ -HiddenHost"
shell.ShellExecute powershellPath, arguments, "", "runas", 0
