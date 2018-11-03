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

USE msdb --Set the database where you would like the tables and stored procdures to be created
GO
CREATE SCHEMA Logs;
GO