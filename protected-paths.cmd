@echo off
set "PP_CLI=%~dp0tools\cli\protected-paths.ps1"
if not exist "%PP_CLI%" set "PP_CLI=%~dp0..\protected-paths.ps1"
if not exist "%PP_CLI%" (
  echo Missing Protected Paths CLI engine. 1>&2
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PP_CLI%" %*
exit /b %ERRORLEVEL%
