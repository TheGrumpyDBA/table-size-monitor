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
/*	Version: 2018-11-03                                                                */
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
