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
USE msdb  --Set the database where you would like the stored procdure created
GO
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
/*	Version: 2018-11-03                                                              */
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
