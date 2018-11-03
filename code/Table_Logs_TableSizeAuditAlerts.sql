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

USE msdb  --Set the database where you would like the objects to be created
GO
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