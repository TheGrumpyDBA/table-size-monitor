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

-- TableSize Monitor UNINSTALL

USE msdb  --Set the database where the tables and stored procdures were created

SET NOCOUNT ON

DECLARE @RemoveJobs		CHAR(1),
		@RemoveTables	CHAR(1),
		@JobNamePrefix	VARCHAR(128),
		@LogJobName		NVARCHAR(128),
		@AlertJobName	NVARCHAR(128),
		@ReturnCode		INT,
		@SQLCommand		VARCHAR(MAX),
		@ErrorMessage	NVARCHAR(MAX);

-- Set UnInstall Parameters.  
SET @RemoveJobs			= 'Y';	-- Set to 'N' if you do not want the SQL Agent jobs to be Removed
SET @RemoveTables		= 'N';	-- Set to 'Y' if you want the tables that store data to be Removed
SET @JobNamePrefix		= NULL;	-- Set the prefix used for all jobs.  
								--		Do not specify if jobs used the default - prefixed with "_Monitor_@@SERVERNAME_TableSize".
SET @LogJobName			= NULL; -- Set the name of the Log Job.  This is only necessary if the job name does not follow the naming standard using the original installation script
SET @AlertJobName		= NULL;	-- Set the name of the Audit Job.  This is only necessary if the job name does not follow the naming standard using the original installation script

/*-------------------------------------------------------------------------------------*/
/* Remove the TableSize Logging and Alert Jobs                                         */
/*-------------------------------------------------------------------------------------*/
IF @RemoveJobs = 'Y'
BEGIN
	IF @LogJobName IS NULL
		SELECT @LogJobName = CASE WHEN @JobNamePrefix IS NULL THEN '_Monitor_' + @@SERVERNAME + '_TableSize_Log' ELSE @JobNamePrefix + '_Log' END;

	IF @AlertJobName IS NULL
		SELECT @AlertJobName = CASE WHEN @JobNamePrefix IS NULL THEN '_Monitor_' + @@SERVERNAME + '_TableSize_Alert' ELSE @JobNamePrefix + '_Audit' END;

	IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @LogJobName)
	BEGIN
		EXEC @ReturnCode = msdb.dbo.sp_delete_job @job_name = @LogJobName;
		IF @ReturnCode = 0
			PRINT 'Job "' + @LogJobName + '" was deleted.';
		ELSE
			PRINT 'ERROR: Job "' + @LogJobName + '" was not deleted.';
	END
	ELSE
		PRINT 'Job "' + @LogJobName + '" was not found.';

	IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @AlertJobName)
	BEGIN
		EXEC @ReturnCode = msdb.dbo.sp_delete_job @job_name = @AlertJobName;
		IF @ReturnCode = 0
			PRINT 'Job "' + @AlertJobName + '" was deleted.';
		ELSE
			PRINT 'ERROR: Job "' + @AlertJobName + '" was not deleted.';
	END
	ELSE
		PRINT 'Job "' + @AlertJobName + '" was not found.';
END;

/*-------------------------------------------------------------------------------------*/
/* Remove the TableSize Stored Procedures                                              */
/*-------------------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.usp_LogTableSizes') AND type in (N'P', N'PC'))
BEGIN
	EXEC @ReturnCode = dbo.sp_executesql @statement = N'DROP PROCEDURE Logs.usp_LogTableSizes';
	IF @ReturnCode = 0
		PRINT 'Stored Procedure "Logs.usp_LogTableSizes" was deleted.';
	ELSE
		PRINT 'ERROR: Stored Procedure "Logs.usp_LogTableSizes" was not deleted.';
END
ELSE
	PRINT 'Stored Procedure "Logs.usp_LogTableSizes" was not found.';

IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.usp_AuditTableSizes') AND type in (N'P', N'PC'))
BEGIN
	EXEC @ReturnCode = dbo.sp_executesql @statement = N'DROP PROCEDURE Logs.usp_AuditTableSizes';
	IF @ReturnCode = 0
		PRINT 'Stored Procedure "Logs.usp_AuditTableSizes" was deleted.';
	ELSE
		PRINT 'ERROR: Stored Procedure "Logs.usp_AuditTableSizes" was not deleted.';
END
ELSE
	PRINT 'Stored Procedure "Logs.usp_AuditTableSizes" was not found.';

/*-------------------------------------------------------------------------------------*/
/* Remove the TableSize Tables and Schema                                              */
/*-------------------------------------------------------------------------------------*/
IF @RemoveTables = 'Y'
BEGIN
	IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.TableSize') AND type in (N'U'))
	BEGIN
		EXEC @ReturnCode = dbo.sp_executesql @statement = N'DROP TABLE Logs.TableSize';
		IF @ReturnCode = 0
			PRINT 'Table "Logs.TableSize" was deleted.';
		ELSE
			PRINT 'ERROR: Table "Logs.TableSize" was not deleted.';
	END
	ELSE
		PRINT 'Table "Logs.TableSize" was not found.';

	IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.TableSizeAuditAlerts') AND type in (N'U'))
	BEGIN
		EXEC @ReturnCode = dbo.sp_executesql @statement = N'DROP TABLE Logs.TableSizeAuditAlerts';
		IF @ReturnCode = 0
			PRINT 'Table "Logs.TableSizeAuditAlerts" was deleted.';
		ELSE
			PRINT 'ERROR: Table "Logs.TableSizeAuditAlerts" was not deleted.';
	END
	ELSE
		PRINT 'Table "Logs.TableSizeAuditAlerts" was not found.';

	IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'Logs.TableSizeAuditOverride') AND type in (N'U'))
	BEGIN
		EXEC @ReturnCode = dbo.sp_executesql @statement = N'DROP TABLE Logs.TableSizeAuditOverride';
		IF @ReturnCode = 0
			PRINT 'Table "Logs.TableSizeAuditOverride" was deleted.';
		ELSE
			PRINT 'ERROR: Table "Logs.TableSizeAuditOverride" was not deleted.';
	END
	ELSE
		PRINT 'Table "Logs.TableSizeAuditOverride" was not found.';

	IF	NOT EXISTS (SELECT 1 FROM sys.objects so INNER JOIN sys.schemas ss ON so.schema_id = ss.schema_id WHERE ss.name = 'Logs') AND
		EXISTS (SELECT 1 FROM sys.schemas ss WHERE ss.name = 'Logs')
	BEGIN
		EXEC @ReturnCode = dbo.sp_executesql @statement = N'DROP SCHEMA Logs';
		IF @ReturnCode = 0
			PRINT 'Schema "Logs" was deleted.';
		ELSE
			PRINT 'ERROR: Schema "Logs" was not deleted.';
	END
	ELSE
		PRINT 'Schema "Logs" was not found.';
END