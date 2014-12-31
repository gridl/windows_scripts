@echo off

:: SQL Backup script for MSSQL or MySQL/MariaDB Databases
:: v2.0 by Orsiris de Jong - http://www.netpower.fr - ozy@netpower.fr
:: 
:: Changelog
:: 30/12/2014 - V2	- Merged earlier versions of MSSQL and MySQL backup scripts into one
::					- Better log file
::					- Added old backup files deletion option
::					- Improved file rotation to deal with all files at once
::					- Added better email handling and logging
:: 20/11/2014 - Fixed a bug when logfile is not specified
:: 27/02/2013 - Added support for backup file rotation
:: Somewhere in 2012 : Quick and dirty backup script for MSSQL
:: Somewhere in 2008 : Quick and dirty backup script for MySQL

:: Server Type (possible values are mssql for Microsft SQL Server or mysql for MySQL / MariaDB servers)
set SERVER_TYPE=mysql
:: Backup destination path (no ending slash)
set BACKUP_PATH=E:\SQL_BACKUPS
:: Use Backup rotation (number of minimum copies to keep)
set ROTATE_BACKUPS=yes
set COPIES=14
:: Delete backups older than X days
set DELETE_OLD_BACKUPS=no
set DELETE_OLD_DAYS=31
:: Compress backed up SQL files
set COMPRESS=1
:: Compress backup logs before sending by email
set COMPRESS_LOGS=1
:: Compression level, 1=fast, 9=best
set COMPRESSLEVEL=9

:: Alert email send options
set SEND_ALERTS=yes
set SMTP_SERVER=smtp.example.com
set SMTP_PORT=587
set SMTP_USER=infra@example.com
:: You can set a clear text SMTP password here
set SMTP_PW=
:: Alternatively, you can provide a B64 encoded password here
set SMTP_PWB64=U29Zb3VUcmllZFRoaXM/IA0K
set SENDER=%SMTP_USER%
set RECEIVER=monitor@example.com
set WARNING_MESSAGE=WARNING, SQL Backup alert
:: Mail server encryption, possible values are tls, ssl, none
set SECURITY=tls

:: MSSQL specific parameters
set MSSQL_INSTANCE=SOMESERVER\INSTANCE

:: MySQL / MariaDB specific parameters
set MYSQL_HOST=127.0.0.1
set MYSQL_USER=root
:: You can set a clear text MySQL password here
set MYSQL_PW=
:: Alternatively, you can provide a B64 encoded password here
set MYSQL_PWB64=TWFpbE1lSWZZb3VMaWtlVGhpcyANCg==
set MYSQL_PORT=3306
set MYSQL_BIN_PATH=C:\Program Files\MariaDB 5.5\bin

:: Misc
:: Get Script working dir to find out where gzip.exe, base64.exe and mailsend.exe executables are.
set curdir=%~dp0
set curdir=%curdir:~0,-1%
:: File containing database list to backup
SET DBLIST=%curdir%\Database-list.txt
:: Log file
set LOG_FILE=%curdir%\Databases-backup.log
:: Set debug flag
set DEBUG=no
:: ---------------------------------------------------------------------------------------------------------------------------

setlocal enabledelayedexpansion

IF "%COMPRESS%"=="1" set COMPRESS_EXTENSION=.gz
IF NOT EXIST "%BACKUP_PATH%" MKDIR "%BACKUP_PATH%"
call:GetComputerName
IF "%ROTATE_BACKUPS%"=="yes" call:RotateCopies
IF "%SERVER_TYPE%"=="mysql" call:MySQLBackupDatabases
IF "%SERVER_TYPE%"=="mssql" call:MSSQLBackupDatabases
IF "%DELETE_OLD_BACKUPS%"=="yes" call:DeleteOldBackups
GOTO END

:GetTime
:: English Date /T returns Day MM/DD/YYYY whereas French one returns DD/MM/YYYY, Try to catch both
FOR /F "tokens=1,2,3,4 delims=/" %%a IN ('Date /T') DO (
IF "%%d"=="" set now_date=%%a-%%b-%%c
IF NOT "%%d"=="" set now_date=%%a-%%b-%%c-%%d
)
set now_time=%TIME:~0,2%:%TIME:~3,2%:%TIME:~6,2%
GOTO:EOF

:Log
call:GetTime
echo %now_date% - %now_time% %~1 >> "%LOG_FILE%"
IF "%DEBUG%"=="yes" echo %~1
GOTO:EOF

:CheckMailValues
echo "%SENDER%" | findstr /I "@" > nul
IF %ERRORLEVEL%==1 (
	call:Log "Source mail not set"
	GOTO End
	)
echo "%RECEIVER%" | findstr /I "@" > nul
IF %ERRORLEVEL%==1 (
	call:Log "Destination Mail not Set"
	GOTO End
	)
IF "%SUBJECT%"=="" (
	call:Log "Mail subject not set"
GOTO End
	)
echo "%SMTP_SERVER%" | findstr /I "." > nul
IF %ERRORLEVEL%==1 (
	call:Log "Smtp sever not set"
	GOTO End
	)
call:Log "Configuration file check success."
GOTO:EOF

:GetComputerName
set COMPUTER_FQDN=%COMPUTERNAME%
IF NOT "%USERDOMAIN%"=="" set COMPUTER_FQDN=%COMPUTERNAME%.%USERDOMAIN%
IF NOT "%USERDNSDOMAIN%"=="" set COMPUTER_FQDN=%COMPUTERNAME%.%USERDNSDOMAIN%
GOTO:EOF

:GetSMTPPw
IF "%SMTP_PW%"=="" IF NOT "%SMTP_PWB64%"=="" FOR /F %%i IN ('"echo %SMTP_PWB64% | "%curdir%\base64.exe" -d"') DO SET SMTP_PW=%%i
GOTO:EOF

:GetMySQLPw
IF "%MYSQL_PW%"=="" IF NOT "%MYSQL_PWB64%"=="" FOR /F %%i IN ('"echo %MYSQL_PWB64% | "%curdir%\base64.exe" -d"') DO SET MYSQL_PW=%%i
GOTO:EOF

:Mailer
IF NOT "%SEND_ALERTS%"=="yes" GOTO:EOF
set SUBJECT=Database Backup error on %COMPUTER_FQDN%
set MAIL_CONTENT=%DATE% - %WARNING_MESSAGE%
call:CheckMailValues
call:SetAttachment
call:MailerMailSend
GOTO:EOF

:SetAttachment
IF %LOG_FILE%=="" GOTO:EOF
IF "%COMPRESS_LOGS%"=="1" (
	for %%I in (%LOG_FILE%) do set compressed_file=%%~nxI
	"%curdir%\gzip.exe" -9 -c "%LOG_FILE%" > "%curdir%\!compressed_file!.gz"
	set attachment=-attach "%curdir%\!compressed_file!.gz"
) ELSE (
	set attachment=-attach "%curdir%\%LOG_FILE%"
)
GOTO:EOF

:MailerMailSend
IF "%SECURITY%"=="tls" set encryption=-starttls
IF "%SECURITY%"=="ssl" set encryption=-ssl

IF NOT "%SMTP_USER%"=="" set smtpuser=-auth -user %SMTP_USER%
call:GetSMTPPw
IF NOT "%SMTP_PW%"=="" set smtppassword=-pass %SMTP_PW%
"%curdir%\mailsend.exe" -f "%SENDER%" -t "%RECEIVER%" -sub "%SUBJECT%" -M "%MAIL_CONTENT%" %attachment% -smtp "%SMTP_SERVER%" -port %SMTP_PORT% %smtpuser% %smtppassword% %encrypt% -log "%LOG_FILE%"
IF NOT %ERRORLEVEL%==0 set SCRIPT_ERROR=1 && call:Log "Sending mail using mailsend failed."
GOTO:EOF

:MySQLBackupDatabases
call:Log "Backing up MySQL databases from %MYSQL_HOST% on computer %COMPUTER_FQDN%"
call:GetMySQLPw
:: Create List of databases to backup
"%MYSQL_BIN_PATH%\mysql.exe" -h %MYSQL_HOST% -P %MYSQL_PORT% -u %MYSQL_USER% --password=%MYSQL_PW% -Bse "SHOW DATABASES;" | find /V "information_schema" | find /V "test" | find /V "performance_schema" > "%DBLIST%"
IF NOT "%ERRORLEVEL%"=="0" call:Log "Cannot get database list from server %MYSQL_HOST%" && call:Mailer && GOTO END

:: Backing up each database in %DBLIST% file
FOR /F "tokens=*" %%i IN (%DBLIST%) DO (
call:Log "Backing up Database: %%i"
IF "%COMPRESS%"=="1" "%MYSQL_BIN_PATH%\mysqldump.exe" -h %MYSQL_HOST% -P %MYSQL_PORT% -u %MYSQL_USER% --password=%MYSQL_PW% --database %%i | "%curdir%\gzip.exe" -%COMPRESSION_LEVEL% -c > "%BACKUP_PATH%\%%i.sql%COMPRESS_EXTENSION%"
IF NOT "%ERRORLEVEL%"=="0" call:Log "Failed backing up database %%i" && set SCRIPT_ERROR=1
IF NOT "%COMPRESS%"=="1" "%MYSQL_BIN_PATH%\mysqldump.exe" -h %MYSQL_HOST% -P %MYSQL_PORT% -u %MYSQL_USER% --password=%MYSQL_PW% --database %%i > "%BACKUP_PATH%\%%i.sql"
IF NOT "%ERRORLEVEL%"=="0" call:Log "Failed backing up database %%i" && set SCRIPT_ERROR=1
)
IF "!SCRIPT_ERROR!"=="1" call:Mailer
GOTO:EOF

:MSSQLBackupDatabases
call:Log "Backing up MSSQL databases from %MSSQL_INSTANCE% on computer %COMPUTER_FQDN%"
:: Create List of databases to backup
SqlCmd -E -S %MSSQL_INSTANCE% -h-1 -W -b -Q "SET NoCount ON; SELECT Name FROM master.dbo.sysDatabases WHERE [Name] NOT IN ('master','model','msdb','tempdb')" > "%DBLIST%"
IF NOT "%ERRORLEVEL%"=="0" call:Log "Cannot get database list from instance %MSSQL_INSTANCE%" && call:Mailer && GOTO END

:: Backup each database in %DBLIST% file
FOR /F "tokens=*" %%i IN (%DBLIST%) DO (
call:Log "Backing up database: %%i"
SqlCmd -E -S %MSSQL_INSTANCE% -b -Q "BACKUP DATABASE [%%i] TO Disk='%BACKUP_PATH%\%%i.bak'"
IF NOT "%ERRORLEVEL%"=="0" call:Log "Failed Backing up database %%i" && set SCRIPT_ERROR=1
IF "%ERRORLEVEL%"=="0" IF "%COMPRESS%"=="1" "%curdir%\gzip.exe" -f "%BACKUP_PATH%\%%i.bak"
)
GOTO:EOF

:RotateCopies
IF "%SERVER_TYPE%"=="mysql" set BACKUP_EXTENSION=.sql%COMPRESS_EXTENSION%
IF "%SERVER_TYPE%"=="mssql" set BACKUP_EXTENSION=.bak%COMPRESS_EXTENSION%
:: Pay attention that !previouscopy! is a expanded variable. %%~nf is the filename without extension (only the last one)
for /R "%BACKUP_PATH%" %%f in (*%BACKUP_EXTENSION%) DO (
	:: Remove compression extension if there is one
	IF NOT "%COMPRESS_EXTENSION%"=="" set filename_no_ext=%%~nf
	:: Remove normal extension too in order to add rotation number before extension
	set filename_no_ext=!filename_no_ext:~0,-4!
	:: Exclude earlier rotated copies with .copynumber by regex: One dot and one or more [0-9] at the end of the filename
	echo !filename_no_ext!| FINDSTR /R "\.[0-9]*$"
	IF NOT "!ERRORLEVEL!"=="0" (
	FOR /L %%i IN (%COPIES%,-1,0) DO (
	SET /A previouscopy = %%i-1
	IF EXIST "%BACKUP_PATH%\!filename_no_ext!.!previouscopy!%BACKUP_EXTENSION%" (
		IF EXIST "%BACKUP_PATH%\!filename_no_ext!.%%i%BACKUP_EXTENSION%" (
			DEL "%BACKUP_PATH%\!filename_no_ext!.%%i%BACKUP_EXTENSION%"
			)
		REN "%BACKUP_PATH%\!filename_no_ext!.!previouscopy!%BACKUP_EXTENSION%" "!filename_no_ext!.%%i%BACKUP_EXTENSION%"
		)
	)
	REN "%BACKUP_PATH%\!filename_no_ext!%BACKUP_EXTENSION%" "!filename_no_ext!.0%BACKUP_EXTENSION%"
	)
)
GOTO:EOF

:DeleteOldBackups
IF "%SERVER_TYPE%"=="mysql" set BACKUP_EXTENSION=.sql%COMPRESS_EXTENSION%
IF "%SERVER_TYPE%"=="mssql" set BACKUP_EXTENSION=.bak%COMPRESS_EXTENSION%
FORFILES /P %BACKUP_PATH% /M *%BACKUP_EXTENSION% /S /D -%DELETE_OLD_DAYS% /C "cmd /c del @PATH" 2> NUL
IF "%ERRORLEVEL%"=="9009" call:Log "Could not delete old backup files. FORFILES command could be missing."
GOTO:EOF

:END
:: Remove Temp file
IF NOT "%DEBUG%"=="yes" IF EXIST "%DBLIST%" DEL /F /S /Q "%DBLIST%"

ENDLOCAL