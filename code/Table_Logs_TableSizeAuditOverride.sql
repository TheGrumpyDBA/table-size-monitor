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

USE msdb  --Set the database where you would like the table created
GO
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