@echo off
rem Windows launcher for the `sandbox` script next to this file. Put this folder
rem on your PATH to run `sandbox` from PowerShell or cmd.
where py >nul 2>&1 && goto py
python "%~dp0sandbox" %*
exit /b %errorlevel%
:py
py "%~dp0sandbox" %*
exit /b %errorlevel%
