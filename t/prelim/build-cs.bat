:: Build a file (%1) using the csc compiler [with options (%2 thru %n)]

:: ====<startup>
@echo off
:: enable extensions
verify aNONExistentFilenameCausingAnErrorLevelOf1 2>nul
setlocal enableextensions enabledelayedexpansion
if ERRORLEVEL 1 echo DIE: Unable to enable extensions

:: ====<config>
:: RESET all config vars
set opts_=
set incs_=
set refs_=
set rezs_=
:: opts_ == csc compiler options
:: refs_ == list of library directories for references (semicolon seperated list, wildcards ok)
:: rezs_ == list of resources to embed/bind
set opts_=/o /nologo
::set incs_=.\include\*.cs
set refs_=..\lib\*.dll;.\lib\*.dll
::set rezs_=..\lib\NDesk.Options.dll
::
:: URLrefs: http://home7.inet.tele.dk/batfiles/basic/chap27.htm#documentation ; http://www.netikka.net/tsneti/info/tscmd010.htm ; http://groups.google.com/group/alt.msdos.batch/msg/f608090e13bfa27f
::
:: check for arguments
if "%1"=="" (echo Usage: build FILE [OPTIONS] & exit /B -1)
::
:: setup Visual Studio environment (vcvars.bat) ?? needed
call vcvars.bat 1>nul
::
:: get filename and extra options
set file_=%1
shift
set exts_=%1
:argLoop
shift
if NOT [%1]==[] ( set exts_=%exts_% %1% )
if NOT [%1]==[] ( goto :argLoop )
:: collect references
if NOT DEFINED incs_ (set "incs_= ")
if NOT DEFINED refs_ (set "refs_= ")
if NOT DEFINED rezs_ (set "rezs_= ")
set sep_=;
for %%g in ("%incs_:;=" "%") do (for %%h in ("%%g") do (call :CollectFiles %%h sep_ i_))
for %%g in ("%refs_:;=" "%") do (for %%h in ("%%g") do (call :CollectFiles %%h sep_ r_))
for %%g in ("%rezs_:;=" "%") do (for %%h in ("%%g") do (call :CollectFiles %%h sep_ z_))
::
::echo i = %i_%
::echo r = %r_%
::echo z = %z_%
::
if DEFINED i_ (set csc_i_=%i_%)
if DEFINED r_ (set csc_r_=/r:%r_%)
if DEFINED z_ (set csc_z_=/res:%z_%)
::
echo [csc %file_% %exts_% %opts_% %csc_i_% %csc_r_% %csc_z_%]
csc %file_% %exts_% %opts_% %csc_i_% %csc_r_% %csc_z_%
::
:: CLEAN-UP
endlocal & goto :EOF
::
:: ==== <subs>
:CollectArgs arg1_ rSep_ rReturn_
:: collect strings into ${$rReturn_} seperated by ${$rSep_}
setlocal enableextensions enabledelayedexpansion
set return_=
set cf_1_=%1
if DEFINED cf_1_ (if NOT DEFINED %3 (set return_="!cf_1_!") ELSE (set return_=!%3!!%2!"!cf_1_!"))
endlocal & set "%3=%return_%"
goto :EOF
::
:CollectFiles arg1_ rSep_ rReturn_
:: collect strings into ${$rReturn_} seperated by ${$rSep_}
setlocal enableextensions enabledelayedexpansion
set return_=
set cf_1_=%1
:: remove any extra surrounding quotes
call :DeQuote cf_1_
call :DeQuote cf_1_
if DEFINED cf_1_ (if NOT DEFINED %3 (set return_="!cf_1_!") ELSE (set return_=!%3!!%2!"!cf_1_!"))
endlocal & set "%3=%return_%"
goto :EOF
::
:DeQuote rReturn_
:: Written by Frank P. Westlake, 2001.09.22, 2001.09.24
:: Modified by Simon Sheppard 2002.06.09   
:: URLref: http://www.ss64.com/nt/syntax-dequote.html , http://www.ss64.com/nt/dequote.txt
set _DeQuoteVar=%1
call set _DeQuoteString=%%!_DeQuoteVar!%%
if [!_DeQuoteString:~0^,1!]==[^"] (
if [!_DeQuoteString:~-1!]==[^"] (
set _DeQuoteString=!_DeQuoteString:~1,-1!
) else (goto :EOF)
) else (goto :EOF)
set !_DeQuoteVar!=!_DeQuoteString!
goto :EOF
