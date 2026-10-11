' Legion Key History: runs update.ps1 -Auto without opening a window (used by the hourly task).
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & folder & "\update.ps1"" -Auto", 0, True
