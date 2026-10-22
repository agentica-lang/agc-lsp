@echo off
setlocal
for %%i in ("%~dp0..") do set "root=%%~fi"
set "binary=%AGENTICA%"
if defined binary goto prepare
for /f "delims=" %%i in ('where agentica 2^>nul') do if not defined binary set "binary=%%i"
if defined binary goto prepare
echo agc-lsp: cannot find 'agentica' 1>&2
exit /b 1
:prepare
set "program="
for /f "delims=" %%i in ('call "%binary%" --allow-run "%root%\bin\prepare.agc" "%root%" "%binary%"') do set "program=%%i"
if not defined program exit /b 1
"%binary%" run --allow-run -- "%program%" %*
exit /b %errorlevel%
