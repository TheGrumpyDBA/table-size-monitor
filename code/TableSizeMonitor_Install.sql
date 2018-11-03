--# -----------------------------------------------------
--# Copyright (C) 2018  Timothy T. Hobbs, The Grumpy DBA

--# This program is free software: you can redistribute it and/or modify
--# it under the terms of the GNU General Public License as published by
--# the Free Software Foundation, either version 3 of the License, or
--# (at your option) any later version.

--# This program is distributed in the hope that it will be useful,
--# but WITHOUT ANY WARRANTY; without even the implied warranty of
--# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--# GNU General Public License for more details.

--# You should have received a copy of the GNU General Public License
--# along with this program.  If not, see <https://www.gnu.org/licenses/>.
--# -----------------------------------------------------
/*-------------------------------------------------------------------------------------*/
/*	GitHub: https://github.com/TheGrumpyDBA/table-size-monitor                         */
/*	Version: 2018-11-03                                                                */
/*	Contact: tim@thegrumpydba.com                                                      */
/*	https://thegrumpydba.com/                                                          */
/*-------------------------------------------------------------------------------------*/

-- TableSize Monitor INSTALL

USE msdb  --Set the database where you would like the tables and stored procdures created

SET NOCOUNT ON

DECLARE @CreateJobs		CHAR(1),
		@JobNamePrefix	VARCHAR(128),
		@DBIncludeList	NVARCHAR(4000),
		@DBExcludeList	NVARCHAR(4000),
		@RowCntLimit	INT,
		@RowPercLimit	INT,
		@RepeatAlerts	VARCHAR(6),
		@Profile_name	SYSNAME,
		@ToRecipients	VARCHAR(MAX),
		@CCRecipients	VARCHAR(MAX),
		@BCCRecipients	VARCHAR(MAX),
		@Subject		NVARCHAR(255),
		@ErrorMessage	NVARCHAR(MAX);

-- Set Instalation Parameters for jobs.  If @CreateJobs = 'N' then remaining parameters are not used.
SET @CreateJobs			= 'Y';	-- Set to 'N' if you do not want the SQL Agent jobs to be created
SET @JobNamePrefix		= NULL;	-- Set the prefix to use for all jobs.  
								--		If not specified, jobs will be prefixed with "_Monitor_@@SERVERNAME_TableSize".
								--		"_Log" and "_Alert" will be appended to the end of the prefix for the two jobs created.
SET @DBIncludeList		= NULL;	-- Comma-delimited list of databases to include.  NULL = ALL databases 
SET @DBExcludeList		= NULL;	-- Comma-delimited list of databases to exclude.  NULL = Do NOT exclude databases 
SET @RowCntLimit		= NULL; -- Alert threshold based on number of rows of data growth. NULL = 1,000,000
SET @RowPercLimit		= NULL; -- Alert threshold based on percentage of rows of data growth.  NULL = 100%
SET @RepeatAlerts		= NULL; -- Flag determining if alerts should be sent every monitor execution or only once.  Options: ONCE or REPEAT
SET @Profile_name		= NULL; -- Profile name to to use for sending alert email.  NULL = Default Profile based on mail settings on server.
SET @ToRecipients		= NULL; -- Semicolon-delimited list of TO recipients. NULL = No TO Recipients
SET @CCRecipients		= NULL; -- Semicolon-delimited list of CC recipients. NULL = No CC Recipients will be included
SET @BCCRecipients		= NULL; -- Semicolon-delimited list of BCC recipients. NULL = No BCC Recipients will be included
SET @Subject			= NULL; -- Subject text to use on alert email. NULL = @@SERVERNAME - Table Size Alert

IF IS_SRVROLEMEMBER('sysadmin') = 0
BEGIN
  SET @ErrorMessage = 'You need to be a member of the SysAdmin server role to install the SQL Server Maintenance Solution.' + CHAR(13) + CHAR(10) + ' '
  RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
END

IF OBJECT_ID('tempdb..#ParmSettings') IS NOT NULL DROP TABLE #ParmSettings

CREATE TABLE #ParmSettings (
	PSName nvarchar(max),
    PSValue nvarchar(max))

INSERT INTO #ParmSettings (PSName, PSValue) VALUES('CreateJobs', @CreateJobs);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('JobNamePrefix', @JobNamePrefix);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('DBIncludeList', @DBIncludeList);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('DBExcludeList', @DBExcludeList);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('RowCntLimit', @RowCntLimit);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('RowPercLimit', @RowPercLimit);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('RepeatAlerts', @RepeatAlerts);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('Profile_name', @Profile_name);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('ToRecipients', @ToRecipients);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('CCRecipients', @CCRecipients);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('BCCRecipients', @BCCRecipients);
INSERT INTO #ParmSettings (PSName, PSValue) VALUES('Subject', @Subject);

/*-------------------------------------------------------------------------------------*/
/* Create the Logs Schema                                                              */
/*-------------------------------------------------------------------------------------*/
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Logs')
BEGIN
	EXEC dbo.sp_executesql @statement = N'CREATE SCHEMA Logs;'
END
GO

/*-------------------------------------------------------------------------------------*/
/* Create the Logs.TableSize Table                                                     */
/*-------------------------------------------------------------------------------------*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.TableSize') AND type in (N'U'))
BEGIN
	CREATE TABLE Logs.TableSize (
		TableSizeID INT identity (1,1) NOT NULL, 
		DatabaseName nvarchar(128) NOT NULL,
		SchemaName	nvarchar(128) NOT NULL,
		TableName	nvarchar(128) NOT NULL,
		CaptureTS	datetime2 NOT NULL,
		RecordCount	int NOT NULL,
		TotalPages int NOT NULL,
		UsedPages int NOT NULL,
		DataPages int NOT NULL,
		TotalSpaceMB int NOT NULL,
		UsedSpaceMB int NOT NULL,
		DataSpaceMB int NOT NULL,
			CONSTRAINT PK_TableSize_K1 PRIMARY KEY CLUSTERED (TableSizeID)
			WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
		);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes where name = 'IX_TableSize_K2_K3_K4_K5')
BEGIN
	CREATE NONCLUSTERED INDEX IX_TableSize_K2_K3_K4_K5 
		ON Logs.TableSize(DatabaseName, SchemaName, TableName, CaptureTS)  
		WITH (FILLFACTOR = 80, PAD_INDEX = ON, DATA_COMPRESSION = PAGE);  
END
GO  

/*-------------------------------------------------------------------------------------*/
/* Create the Logs.TableSizeAuditAlerts Table                                          */
/*-------------------------------------------------------------------------------------*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.TableSizeAuditAlerts') AND type in (N'U'))
BEGIN
	CREATE TABLE Logs.TableSizeAuditAlerts (
			TableSizeAuditAlertsID INT NOT NULL IDENTITY(1,1),
			DatabaseName NVARCHAR(128),
			SchemaName NVARCHAR(128),
			TableName NVARCHAR(128),
			StartRecordCount INT,
			AlertRecordCount INT,
			RowCntLimit INT,
			RowPercLimit INT,
			ToRecipients VARCHAR(MAX),
			CCRecipients VARCHAR(MAX),
			BCCRecipients VARCHAR(MAX),
			AlertTS datetime2,
			CONSTRAINT PK_TableSizeAuditAlerts_K1 PRIMARY KEY CLUSTERED (TableSizeAuditAlertsID)
			WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
		);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes where name = 'IX_TableSizeAuditAlerts_K2_K3_K4_K12')
BEGIN
	CREATE NONCLUSTERED INDEX IX_TableSizeAuditAlerts_K2_K3_K4_K12 
		ON Logs.TableSizeAuditAlerts(DatabaseName, SchemaName, TableName, AlertTS)  
		WITH (FILLFACTOR = 80, PAD_INDEX = ON, DATA_COMPRESSION = PAGE);  
END
GO  

/*-------------------------------------------------------------------------------------*/
/* Create the Logs.TableSizeAuditOverride Table                                        */
/*-------------------------------------------------------------------------------------*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.TableSizeAuditOverride') AND type in (N'U'))
BEGIN
	CREATE TABLE Logs.TableSizeAuditOverride (
		TableSizeAuditOverrideID INT IDENTITY (1,1) NOT NULL, 
		DatabaseName nvarchar(128) NOT NULL,
		SchemaName	NVARCHAR(128) NOT NULL,
		TableName	NVARCHAR(128) NOT NULL,
		RowCntLimit	INT NOT NULL,
		RowPercLimit INT NOT NULL,
			CONSTRAINT PK_TableSizeAuditOverride_K1 PRIMARY KEY CLUSTERED (TableSizeAuditOverrideID)
			WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
		);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes where name = 'IX_TableSizeAuditOverride_K2_K3_K4_i5_i6')
BEGIN
	CREATE NONCLUSTERED INDEX IX_TableSizeAuditOverride_K2_K3_K4_i5_i6
		ON Logs.TableSizeAuditOverride(DatabaseName, SchemaName, TableName)  
			INCLUDE(RowCntLimit, RowPercLimit)
		WITH (FILLFACTOR = 80, PAD_INDEX = ON, DATA_COMPRESSION = PAGE);  
END;
GO  

/*-------------------------------------------------------------------------------------*/
/* Create the Logs.usp_LogTableSizes Stored Procedure                                  */
/*-------------------------------------------------------------------------------------*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.usp_LogTableSizes') AND type in (N'P', N'PC'))
BEGIN
	EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE Logs.usp_LogTableSizes AS SELECT 1'
END
GO
ALTER PROCEDURE Logs.usp_LogTableSizes
	@pDBIncludeList NVARCHAR(4000) = NULL,
	@pDBExcludeList NVARCHAR(4000) = NULL
AS
BEGIN;
/****************************************************************************************
/*-------------------------------------------------------------------------------------*/
/*	GitHub: https://github.com/TheGrumpyDBA/table-size-monitor                         */
/*	Version: 2018-10-31                                                                */
/*	Contact: tim@thegrumpydba.com                                                      */
/*	https://thegrumpydba.com/                                                          */
/*-------------------------------------------------------------------------------------*/
	This stored procedure logs the sizes of all tables within the databases either 
	included in the @pDBIncludeList or not in the @pDBExcludeList.

	This procedure should be run daily to support the Table Size Audit.

	Paramters:
		@pDBIncludeList	Comma-delimited list of databases to include.  
							Default = NULL - Include all databases
		@pDBExcludeList	Comma-delimited list of databases to exclude
							Default = NULL - Do not exclude any databases

****************************************************************************************/
	SET NOCOUNT ON;

	-- Declare variables
	DECLARE @DBList TABLE (
		DBListID INT NOT NULL IDENTITY(1,1),
		DBName NVARCHAR(128));

	DECLARE @vDBIncludeList XML,
			@vDBExcludeList XML,
			@vID INT = 1,
			@vDBName NVARCHAR(128),
			@vSQLCommand NVARCHAR(MAX)

	-- Convert comma-delimited lists of database names into XML
	SELECT @vDBIncludeList = CAST('<A>'+ REPLACE(@pDBIncludeList,',','</A><A>')+ '</A>' AS XML);
	SELECT @vDBExcludeList = CAST('<A>'+ REPLACE(@pDBExcludeList,',','</A><A>')+ '</A>' AS XML);

	-- Get list of databases to monitor
	INSERT INTO @DBList (DBName)
	SELECT name
	FROM master.sys.databases
	WHERE name IN (CASE WHEN @pDBIncludeList IS NULL or @pDBIncludeList = '' 
						THEN name 
						ELSE (SELECT t.value('.', 'nvarchar(128)') FROM @vDBIncludeList.nodes('/A') AS x(t))
					END)
	  AND name NOT IN (SELECT t.value('.', 'nvarchar(128)') FROM @vDBExcludeList.nodes('/A') AS x(t));

	-- Loop over databases in the list capturing the current table sizes
	WHILE @vID <= (SELECT MAX(DBListID) FROM @DBList)
	BEGIN;
		SELECT @vDBName = DBName
		FROM @DBList
		WHERE DBListID = @vID;

		SET @vSQLCommand = 'USE [' + @vDBName + '] 
		INSERT INTO ' + DB_Name() + '.Logs.TableSize
			(DatabaseName, SchemaName, TableName, CaptureTS, RecordCount, TotalPages, UsedPages, DataPages, TotalSpaceMB, UsedSpaceMB, DataSpaceMB)
		SELECT	db_name() AS DatabaseName, s.name AS SchemaName, t.NAME AS TableName, GETDATE() AS CaptureTS, p.[Rows] AS RecordCount, 
				sum(a.total_pages) AS TotalPages, sum(a.used_pages) AS UsedPages, sum(a.data_pages) AS DataPages,
				(sum(a.total_pages) * 8) / 1024 AS TotalSpaceMB, (sum(a.used_pages) * 8) / 1024 AS UsedSpaceMB, 
				(sum(a.data_pages) * 8) / 1024 AS DataSpaceMB
		FROM	sys.tables t
				INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
				INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
				INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
				INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
		WHERE	i.index_id <= 1 and t.NAME NOT LIKE ''dt%'' AND i.OBJECT_ID > 255
		GROUP BY	s.name, t.NAME, p.[Rows]
		ORDER BY	s.name, t.NAME';

		EXEC (@vSQLCommand);
		SET @vID += 1;
	END;

	SET NOCOUNT OFF;
END;
GO

/*-------------------------------------------------------------------------------------*/
/* Create the Logs.usp_AuditTableSizes Stored Procedure                                */
/*-------------------------------------------------------------------------------------*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.usp_AuditTableSizes') AND type in (N'P', N'PC'))
BEGIN
	EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE Logs.usp_AuditTableSizes AS SELECT 1'
END
GO
ALTER PROCEDURE Logs.usp_AuditTableSizes
	@pDBIncludeList NVARCHAR(4000) = NULL,
	@pDBExcludeList NVARCHAR(4000) = NULL,
	@pRowCntLimit INT = 1000000,
	@pRowPercLimit INT = 100,
	@pRepeatAlerts VARCHAR(6) = 'ONCE',
	@pProfile_name SYSNAME = NULL,
	@pToRecipients VARCHAR(MAX) = NULL,
	@pCCRecipients VARCHAR(MAX) = NULL,
	@pBCCRecipients VARCHAR(MAX) = NULL,
	@pSubject NVARCHAR(255) = NULL
AS
BEGIN;
/****************************************************************************************
/*-------------------------------------------------------------------------------------*/
/*	GitHub: https://github.com/TheGrumpyDBA/table-size-monitor                         */
/*	Version: 2018-10-31                                                                */
/*	Contact: tim@thegrumpydba.com                                                      */
/*	https://thegrumpydba.com/                                                          */
/*-------------------------------------------------------------------------------------*/
		This stored procedure performs an audit on the table growth for all tables
		within the included datablases or not within the excluded databases.  
		It compares the current size of the tables to the most recent daily logged 
		size and sends an alert if any table has grown by either record count or 
		percentage more than the parameters.  

		Override values can be set for individual tables in the 
		Logs.TableSizeAuditOverride table

		Alert Threshold Parameters
		@pDBIncludeList	Comma-delimited list of databases to include.  
							Default = NULL - Include all databases
		@pDBExcludeList	Comma-delimited list of databases to exclude
							Default = NULL - Do not exclude any databases
		@pRowCntLimit	Default Alert threshold based on number of rows of data growth 
							Default = 1,000,000
		@pRowPercLimit	Default Alert threshold based on percentage of rows of data growth
							Default = 100 (%)
		@pRepeatAlerts	Flag determining if alerts should be sent every monitor execution or only once
							Default = ONCE	(Options: ONCE or REPEAT)

		Notification Parameters
		@pProfile_name	Profile name to to use for sending alert email
							Default = NULL - Use default profile
		@pToRecipients	Semicolon-delimited list of TO recipients.
							Default = NULL - No TO Recipients
		@pCCRecipients	Semicolon-delimited list of CC recipients.
							Default = NULL - No CC Recipients will be included
		@pBCCRecipients Semicolon-delimited list of BCC recipients.
							Default = NULL - No BCC Recipients will be included
		@pSubject		Subject text to use on alert email
							Default = NULL - @@SERVERNAME - Table Size Alert

****************************************************************************************/
	SET NOCOUNT ON;

	-- Declare variables
	DECLARE @DBList TABLE (
		DBListID INT NOT NULL IDENTITY(1,1),
		DBName NVARCHAR(128));

	IF EXISTS (SELECT 1 FROM tempdb.sys.objects where name = '##CurrTableSize')
	BEGIN
		DROP TABLE ##CurrTableSize
	END

	CREATE TABLE ##CurrTableSize (
		TableSizeID INT identity (1,1) NOT NULL, 
		DatabaseName nvarchar(128) NOT NULL,
		SchemaName	nvarchar(128) NOT NULL,
		TableName	nvarchar(128) NOT NULL,
		CaptureTS	datetime2 NOT NULL,
		RecordCount	int NOT NULL,
		TotalPages int NOT NULL,
		UsedPages int NOT NULL,
		DataPages int NOT NULL,
		TotalSpaceMB int NOT NULL,
		UsedSpaceMB int NOT NULL,
		DataSpaceMB int NOT NULL
		);

	DECLARE @AlertResult TABLE (
		AlertResultID INT NOT NULL IDENTITY(1,1),
		DatabaseName NVARCHAR(128),
		SchemaName NVARCHAR(128),
		TableName NVARCHAR(128),
		CurrCaptureTS datetime2,
		PrevCaptureTS datetime2,
		CurrRecordCount INT,
		PrevRecordCount INT,
		CurrTotalSpaceMB INT,
		RowCntLimit INT,
		RowPercLimit INT
		);

	DECLARE @vDBIncludeList XML,
			@vDBExcludeList XML,
			@vID INT = 1,
			@vDBName NVARCHAR(128),
			@vSQLCommand NVARCHAR(MAX),
			@vSubject NVARCHAR(255),
			@vSchemaName NVARCHAR(128),
			@vTableName NVARCHAR(128),
			@vCurrCaptureTS datetime2,
			@vPrevCaptureTS datetime2,
			@vCurrRecordCount INT,
			@vPrevRecordCount INT,
			@vCurrTotalSpaceMB INT,
			@vRowCntLimit INT, 
			@vRowPercLimit INT,
			@vCellClass VARCHAR(10);

	-- Convert comma-delimited lists of database names into XML
	SELECT @vDBIncludeList = CAST('<A>'+ REPLACE(@pDBIncludeList,',','</A><A>')+ '</A>' AS XML);
	SELECT @vDBExcludeList = CAST('<A>'+ REPLACE(@pDBExcludeList,',','</A><A>')+ '</A>' AS XML);

	-- Get list of databases to monitor
	INSERT INTO @DBList (DBName)
	SELECT name
	FROM master.sys.databases
	WHERE name IN (CASE WHEN @pDBIncludeList IS NULL or @pDBIncludeList = '' 
						THEN name 
						ELSE (SELECT t.value('.', 'nvarchar(128)') FROM @vDBIncludeList.nodes('/A') AS x(t))
					END)
	  AND name NOT IN (SELECT t.value('.', 'nvarchar(128)') FROM @vDBExcludeList.nodes('/A') AS x(t));

	-- Loop over databases in the list capturing the current table sizes
	WHILE @vID <= (SELECT MAX(DBListID) FROM @DBList)
	BEGIN;
		SELECT @vDBName = DBName
		FROM @DBList
		WHERE DBListID = @vID;

		SET @vSQLCommand = 'USE [' + @vDBName + '] 
		INSERT INTO ##CurrTableSize
			(DatabaseName, SchemaName, TableName, CaptureTS, RecordCount, TotalPages, UsedPages, DataPages, TotalSpaceMB, UsedSpaceMB, DataSpaceMB)
		SELECT	db_name() AS DatabaseName, s.name AS SchemaName, t.NAME AS TableName, GETDATE() AS CaptureTS, p.[Rows] AS RecordCount, 
				sum(a.total_pages) AS TotalPages, sum(a.used_pages) AS UsedPages, sum(a.data_pages) AS DataPages,
				(sum(a.total_pages) * 8) / 1024 AS TotalSpaceMB, (sum(a.used_pages) * 8) / 1024 AS UsedSpaceMB, 
				(sum(a.data_pages) * 8) / 1024 AS DataSpaceMB
		FROM	sys.tables t
				INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
				INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
				INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
				INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
		WHERE	i.index_id <= 1 and t.NAME NOT LIKE ''dt%'' AND i.OBJECT_ID > 255
		GROUP BY	s.name, t.NAME, p.[Rows]
		ORDER BY	s.name, t.NAME';

		EXEC (@vSQLCommand);
		SET @vID += 1;
	END;

	-- Load tables that are over the alert threshold into the @AlertResult table
	INSERT INTO @AlertResult
		(DatabaseName, SchemaName, TableName, CurrCaptureTS, PrevCaptureTS, CurrRecordCount, PrevRecordCount, CurrTotalSpaceMB, RowCntLimit, RowPercLimit)
	SELECT	curr.DatabaseName, curr.SchemaName, curr.TableName, curr.CaptureTS, prev.CaptureTS,
			curr.RecordCount as CurrRecordCourt, prev.RecordCount PrevRecordCount, curr.TotalSpaceMB,
			COALESCE(tsao.RowCntLimit, @pRowCntLimit) as RowCntLimit,
			COALESCE(tsao.RowPercLimit, @pRowPercLimit) as RowPercLimit
	FROM ##CurrTableSize curr
		INNER JOIN Logs.TableSize prev 
				ON	curr.DatabaseName = prev.DatabaseName AND
					curr.SchemaName = prev.SchemaName AND
					curr.TableName = prev.TableName
		LEFT OUTER JOIN Logs.TableSizeAuditOverride tsao
				ON	curr.DatabaseName = tsao.DatabaseName AND
					curr.SchemaName = tsao.SchemaName AND
					curr.TableName = tsao.TableName
	WHERE	curr.DatabaseName in (SELECT DBName FROM @DBList)
			AND
			prev.TableSizeID = 
				(SELECT MAX(t1.TableSizeID) 
					FROM Logs.TableSize t1 
					WHERE 	t1.DatabaseName = curr.DatabaseName AND
						t1.SchemaName = curr.SchemaName AND
						t1.TableName = curr.TableName)
			AND 
			((curr.RecordCount - prev.RecordCount > COALESCE(tsao.RowCntLimit, @pRowCntLimit)) OR
				(cast((curr.RecordCount - prev.RecordCount) as decimal(19,3)) / 
				 cast(CASE WHEN prev.RecordCount = 0 AND curr.RecordCount = 0  THEN 1 WHEN prev.RecordCount = 0 THEN curr.RecordCount ELSE prev.RecordCount END as decimal(19,3))) * 100 > COALESCE(tsao.RowPercLimit, @pRowPercLimit))
				;

	-- If Alerts should only be sent once, then remove alerts from the result table that already have an alert for the current day.
	IF @pRepeatAlerts = 'ONCE'
	BEGIN
		DELETE ar
		FROM @AlertResult ar
		WHERE EXISTS 
				(SELECT 1 FROM Logs.TableSizeAuditAlerts tsaa 
				 WHERE  tsaa.DatabaseName = ar.DatabaseName AND
						tsaa.SchemaName = ar.SchemaName AND
						tsaa.TableName = ar.TableName AND
						tsaa.AlertTS > CAST(GETDATE() as date));
	END

	-- If there were any rows inserted into @AlertResult, send an email and log the results
	IF (SELECT COUNT(*) FROM @AlertResult) > 0
	BEGIN
		SET @vSQLCommand = 'exec msdb.dbo.sp_send_dbmail ';
		IF @pProfile_name IS NOT NULL
		BEGIN
			SET @vSQLCommand = @vSQLCommand + '@profile_name = ''' + @pProfile_name + ''', ';
		END;
		SET @vSQLCommand = @vSQLCommand + '@recipients = ''' + @pToRecipients + ''', ';
		IF @pCCRecipients IS NOT NULL
		BEGIN
			SET @vSQLCommand = @vSQLCommand + '@copy_recipients = ''' + @pCCRecipients + ''', ';
		END;
		IF @pBCCRecipients IS NOT NULL
		BEGIN
			SET @vSQLCommand = @vSQLCommand + '@blind_copy_recipients = ''' + @pBCCRecipients + ''', ';
		END;
		IF @pSubject IS NOT NULL
		BEGIN
			SET @vSQLCommand = @vSQLCommand + '@subject = ''' + @pSubject + ''', ';
		END
		ELSE
		BEGIN
			SELECT @vSQLCommand = @vSQLCommand + '@subject = ''' + @@SERVERNAME + ' - Table Size Alert'',';
		END;
		SET @vSQLCommand = @vSQLCommand + '@body = ''' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<style type="text/css">' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '.tg  {border-collapse:collapse;border-spacing:0;}' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '.tg td{font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:black;}' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '.tg th{font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:black;}' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '.tg .tg-r6a2{font-size:12px;text-align:left;vertical-align:top}' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '.tg .tg-2n9k{font-weight:bold;font-size:14px;background-color:#96fffb;text-align:left;vertical-align:top}' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '.tg .tg-aabp{font-size:12px;background-color:#efefef;text-align:left;vertical-align:top}' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '</style>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + 'The tables listed below have grown more than their alert thresholds!<br /><br />' + CHAR(13) + CHAR(10);
		If @pRepeatAlerts = 'ONCE'
		BEGIN
			SET @vSQLCommand = @vSQLCommand + 'Alerts are not going to be repeated!  You will not receive another email today for these tables. <br /><br />' + CHAR(13) + CHAR(10);
		END
		ELSE
		BEGIN
			SET @vSQLCommand = @vSQLCommand + 'Alerts will be repeated until the issue with the table(s) are resolved or until the end of the current day!<br /><br />' + CHAR(13) + CHAR(10);
		END;
		SET @vSQLCommand = @vSQLCommand + '<table class="tg">' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<tr>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Database</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Schema</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Table</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Current Capture Time</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Previous Capture Time</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Current Record Count</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Previous Record Count</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Table Growth (Count)</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Table Growth (Percent)</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Current Table Size (MB)</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Row Count Limit</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '<th class="tg-2n9k">Row Percent Limit</th>' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + '</tr>' + CHAR(13) + CHAR(10);

		SET @vID = 1;
		WHILE @vID <= (SELECT MAX(AlertResultID) FROM @AlertResult)
		BEGIN
			SELECT  @vDBName = DatabaseName, @vSchemaName = SchemaName, @vTableName = TableName, @vCurrCaptureTS = CurrCaptureTS,
					@vPrevCaptureTS = PrevCaptureTS, @vCurrRecordCount = CurrRecordCount, @vPrevRecordCount = PrevRecordCount,
					@vCurrTotalSpaceMB = CurrTotalSpaceMB, @vRowCntLimit = RowCntLimit, @vRowPercLimit = RowPercLimit
			FROM @AlertResult
			WHERE AlertResultID = @vID;

			IF @vID % 2 = 1
			BEGIN
				SET @vCellClass = 'tg-r6a2';
			END
			ELSE
			BEGIN
				SET @vCellClass = 'tg-aabp';
			END;
			SET @vSQLCommand = @vSQLCommand + '<tr>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + @vDBName + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + @vSchemaName + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + @vTableName + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CONVERT(VARCHAR(20), @vCurrCaptureTS, 120) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CONVERT(VARCHAR(20), @vPrevCaptureTS, 120) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CAST(@vCurrRecordCount AS VARCHAR(25)) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CAST(@vPrevRecordCount AS VARCHAR(25)) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CAST(@vCurrRecordCount - @vPrevRecordCount AS VARCHAR(25)) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CAST(CAST((cast((@vCurrRecordCount - @vPrevRecordCount) as decimal(19,3)) / cast(CASE WHEN @vPrevRecordCount = 0 AND @vCurrRecordCount = 0  THEN 1 WHEN @vPrevRecordCount = 0 THEN @vCurrRecordCount ELSE @vPrevRecordCount END as decimal(19,3))) * 100.00 AS DECIMAL(19,3)) AS VARCHAR(25)) + ' %</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CAST(@vCurrTotalSpaceMB AS VARCHAR(25)) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CAST(@vRowCntLimit AS VARCHAR(25)) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '<td class="' + @vCellClass + '">' + CAST(@vRowPercLimit AS VARCHAR(25)) + '</td>' + CHAR(13) + CHAR(10);
			SET @vSQLCommand = @vSQLCommand + '</tr>' + CHAR(13) + CHAR(10);
			SET @vID += 1;
		END
		SET @vSQLCommand = @vSQLCommand + '</table><br /><br />' + CHAR(13) + CHAR(10);
		SET @vSQLCommand = @vSQLCommand + ' Powered by <a href="https://thegrumpydba.com">The Grumpy DBA Table Size Monitor</a>.  '', ';
		SET @vSQLCommand = @vSQLCommand + '@body_format=''HTML''';
		EXEC (@vSQLCommand);

		-- Insert into the alert log
		INSERT INTO Logs.TableSizeAuditAlerts 
			(DatabaseName,SchemaName,TableName,StartRecordCount,AlertRecordCount,RowCntLimit,RowPercLimit,ToRecipients,CCRecipients,BCCRecipients,AlertTS)
		SELECT  ar.DatabaseName, ar.SchemaName, ar.TableName, ar.PrevRecordCount, ar.CurrRecordCount, COALESCE(tsao.RowCntLimit, @pRowCntLimit) as RowCntLimit,
				COALESCE(tsao.RowPercLimit, @pRowPercLimit) as RowPercLimit, @pToRecipients, @pCCRecipients, @pBCCRecipients, GETDATE()
		FROM @AlertResult ar
			LEFT OUTER JOIN Logs.TableSizeAuditOverride tsao
				ON	ar.DatabaseName = tsao.DatabaseName AND
					ar.SchemaName = tsao.SchemaName AND
					ar.TableName = tsao.TableName
	END;

	SET NOCOUNT OFF;
END;
GO

/*-------------------------------------------------------------------------------------*/
/* Create the TableSize Logging and Alert Jobs                                         */
/*-------------------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM #ParmSettings WHERE PSName = 'CreateJobs' AND PSValue = 'Y')
BEGIN

	DECLARE @JobNamePrefix	VARCHAR(128),
			@DBIncludeList	NVARCHAR(4000),
			@DBExcludeList	NVARCHAR(4000),
			@RowCntLimit	INT,
			@RowPercLimit	INT,
			@RepeatAlerts	VARCHAR(6),
			@Profile_name	SYSNAME,
			@ToRecipients	VARCHAR(MAX),
			@CCRecipients	VARCHAR(MAX),
			@BCCRecipients	VARCHAR(MAX),
			@Subject		NVARCHAR(255),
			@LogJobName		NVARCHAR(128),
			@AlertJobName	NVARCHAR(128),
			@JobCategory	SYSNAME,
			@JobDescription	NVARCHAR(512),
			@JobOwner		VARCHAR(128),
			@JobStepCommand	NVARCHAR(MAX),
			@JobStepParms	NVARCHAR(MAX) = '',
			@Databasename	SYSNAME;

	SELECT @JobNamePrefix = PSValue FROM #ParmSettings WHERE PSName = 'JobNamePrefix';
	SELECT @DBIncludeList = PSValue FROM #ParmSettings WHERE PSName = 'DBIncludeList';
	SELECT @DBExcludeList = PSValue FROM #ParmSettings WHERE PSName = 'DBExcludeList';
	SELECT @RowCntLimit = PSValue FROM #ParmSettings WHERE PSName = 'RowCntLimit';
	SELECT @RowPercLimit = PSValue FROM #ParmSettings WHERE PSName = 'RowPercLimit';
	SELECT @RepeatAlerts = PSValue FROM #ParmSettings WHERE PSName = 'RepeatAlerts';
	SELECT @Profile_name = PSValue FROM #ParmSettings WHERE PSName = 'Profile_name';
	SELECT @ToRecipients = PSValue FROM #ParmSettings WHERE PSName = 'ToRecipients';
	SELECT @CCRecipients = PSValue FROM #ParmSettings WHERE PSName = 'CCRecipients';
	SELECT @BCCRecipients = PSValue FROM #ParmSettings WHERE PSName = 'BCCRecipients';
	SELECT @Subject = PSValue FROM #ParmSettings WHERE PSName = 'Subject';

	SELECT @LogJobName = CASE WHEN @JobNamePrefix IS NULL THEN '_Monitor_' + @@SERVERNAME + '_TableSize_Log' ELSE @JobNamePrefix + '_Log' END;
	SET @JobOwner = SUSER_SNAME(0x01);
	SET @JobCategory = 'Data Collector';
	SET @JobDescription = 'Table Size Monitor.  Developed by The Grumpy DBA - https:\\thegrumpydba.com.';
	SET @Databasename = DB_NAME();
	SET @JobStepCommand = N'EXEC Logs.usp_LogTableSizes ';
	SET @JobStepParms = CASE WHEN @DBIncludeList IS NULL THEN '' ELSE '@pDBIncludeList=''' + @DBIncludeList + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @DBExcludeList IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @DBExcludeList IS NULL THEN '' ELSE '@pDBExcludeList=''' + @DBExcludeList + '''' END;
	SET @JobStepParms = @JobStepParms + ';';
	SET @JobStepCommand = @JobStepCommand + @JobStepParms;

	EXECUTE msdb.dbo.sp_add_job @job_name = @LogJobName, @description = @JobDescription, @category_name = @JobCategory, @owner_login_name = @JobOwner;
	EXECUTE msdb.dbo.sp_add_jobstep @job_name = @LogJobName, @step_name = 'usp_LogTableSizes', @subsystem = 'TSQL', @command = @JobStepCommand, @database_name = @Databasename;
	EXECUTE msdb.dbo.sp_add_jobserver @job_name = @LogJobName;

	SELECT @AlertJobName = CASE WHEN @JobNamePrefix IS NULL THEN '_Monitor_' + @@SERVERNAME + '_TableSize_Alert' ELSE @JobNamePrefix + '_Audit' END;
	SET @JobStepCommand = N'EXEC Logs.usp_AuditTableSizes ';
	SET @JobStepParms = CASE WHEN @DBIncludeList IS NULL THEN '' ELSE '@pDBIncludeList=''' + @DBIncludeList + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @DBExcludeList IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @DBExcludeList IS NULL THEN '' ELSE '@pDBExcludeList=''' + @DBExcludeList + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @RowCntLimit IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @RowCntLimit IS NULL THEN '' ELSE '@pRowCntLimit=' + CAST(@RowCntLimit AS VARCHAR(50)) END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @RowPercLimit IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @RowPercLimit IS NULL THEN '' ELSE '@pRowPercLimit=' + CAST(@RowPercLimit AS VARCHAR(50)) END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @RepeatAlerts IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @RepeatAlerts IS NULL THEN '' ELSE '@pRepeatAlerts=''' + @RepeatAlerts + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @Profile_name IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @Profile_name IS NULL THEN '' ELSE '@pProfile_name=''' + @Profile_name + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @ToRecipients IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @ToRecipients IS NULL THEN '' ELSE '@pToRecipients=''' + @ToRecipients + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @CCRecipients IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @CCRecipients IS NULL THEN '' ELSE '@pCCRecipients=''' + @CCRecipients + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @BCCRecipients IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @BCCRecipients IS NULL THEN '' ELSE '@pBCCRecipients=''' + @BCCRecipients + '''' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @JobStepParms <> '' AND RIGHT(@JobStepParms, 2) <> ', ' AND @Subject IS NOT NULL THEN ', ' ELSE '' END;
	SET @JobStepParms = @JobStepParms + CASE WHEN @Subject IS NULL THEN '' ELSE '@pSubject=''' + @Subject + '''' END;
	SET @JobStepParms = @JobStepParms + ';';
	SET @JobStepCommand = @JobStepCommand + @JobStepParms;

	EXECUTE msdb.dbo.sp_add_job @job_name = @AlertJobName, @description = @JobDescription, @category_name = @JobCategory, @owner_login_name = @JobOwner;
	EXECUTE msdb.dbo.sp_add_jobstep @job_name = @AlertJobName, @step_name = 'usp_AuditTableSizes', @subsystem = 'TSQL', @command = @JobStepCommand, @database_name = @Databasename;
	EXECUTE msdb.dbo.sp_add_jobserver @job_name = @AlertJobName;

END
