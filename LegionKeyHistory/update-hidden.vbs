' Legion Key History: runs update.ps1 without opening a window (used by the hourly task).
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & folder & "\update.ps1""", 0, True
