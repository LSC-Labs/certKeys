@echo off
setlocal DisableDelayedExpansion
if exist "%~dp0certKeys.ps1" goto run
>&2 echo [E] Missing "%~dp0certKeys.ps1". Place certKeys.bat and certKeys.ps1 in the same directory.
exit /b 1

:run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0certKeys.ps1" %*
exit /b %errorlevel%
