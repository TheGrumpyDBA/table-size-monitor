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