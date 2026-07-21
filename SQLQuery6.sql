USE [DWH_CL_ESTIM]
GO

/****** Object:  StoredProcedure [dbo].[PS_CHARGEMENT_CSV_ODS]    Script Date: 21/07/2026 09:53:33 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[PS_CHARGEMENT_CSV_ODS] @par_ID_TRT_ALI NVARCHAR(20), @par_PathLib NVARCHAR(200), @par_projectName	NVARCHAR(50)
AS
BEGIN
	SET NOCOUNT ON;

	-- Declaration des variables
	DECLARE
		@ID_TRT_ALI		NVARCHAR(20),
		@PathLib		NVARCHAR(200),
		@Path1			NVARCHAR(200),
		@projectName	NVARCHAR(50),
		@sourceName		NVARCHAR(50),
		@targetName		NVARCHAR(50),
		@dateDebTrt		NVARCHAR(30),
		@dateFinTrt		NVARCHAR(30),
		@rowCount		INT,
		@SQLCommand		NVARCHAR(MAX);

	SET @PathLib	= @par_PathLib;
	SET @ID_TRT_ALI	= @par_ID_TRT_ALI;
	SET @projectName= @par_projectName;

	-- Curseur pour parcourir la liste des tables
	DECLARE tables_cursor CURSOR FOR SELECT [LB_SOURCE], [LB_TABLE_ODS] FROM [ods].[PARAM_CHARGEMENT] WHERE [LB_PROJET] = @projectName AND [NO_CHAMP]=1 AND [FL_CHARGEMENT]=1

	OPEN tables_cursor
	FETCH NEXT FROM tables_cursor INTO @sourceName, @targetName

	WHILE @@FETCH_STATUS = 0
	BEGIN
		BEGIN TRY
			print '*************************************************'
			print 'Integration : ' + @sourceName + ' -> '+ @targetName

			-- annule / remplace des tables ODS
			SET @Path1 = @PathLib + '\\' + @sourceName
			SET @SQLCommand =
			'TRUNCATE TABLE [ods].' + @targetName + ';
			BULK INSERT [ods].' + @targetName + ' FROM ''' + @Path1 + ''' WITH (FIELDTERMINATOR = ''|'', ROWTERMINATOR = ''\n'', FIRSTROW = 1, CODEPAGE=''ACP'', MAXERRORS = 0);
			SET @rowCount = @@ROWCOUNT;';
			print @SQLCommand

			-- Execution du SQL
			SET @dateDebTrt = CONVERT(NVARCHAR(30), GETDATE(), 121);
			EXEC sp_executesql @SQLCommand, N'@rowCount INT OUTPUT', @rowCount = @rowCount OUTPUT;
			print 'Nombre de lignes : ' + CAST(@rowCount AS NVARCHAR);
			SET @dateFinTrt = CONVERT(NVARCHAR(30), GETDATE(), 121);

			-- Table AUDIT
			SET @SQLCommand = 'INSERT INTO [ods].[AUDIT_CHARGEMENT] VALUES (' + @ID_TRT_ALI + ',''' + @projectName + ''', ''Chargement csv -> ods'', ''' + @sourceName + ''',''' + @targetName +''', ' + CAST(@rowCount AS NVARCHAR) + ', ''OK'', NULL, CONVERT(DATETIME, '''+ @dateDebTrt +''',121), CONVERT(DATETIME, '''+ @dateFinTrt +''',121))';
			EXEC sp_executesql @SQLCommand
		END TRY
		BEGIN CATCH
			SET @dateFinTrt = CONVERT(NVARCHAR(30), GETDATE(), 121);
			SET @SQLCommand = 'INSERT INTO [ods].[AUDIT_CHARGEMENT] VALUES (' + @ID_TRT_ALI + ',''' + @projectName + ''', ''Chargement csv -> ods'', ''' + @sourceName + ''',''' + @targetName +''', 0, ''KO'', ERROR_MESSAGE(), CONVERT(DATETIME, '''+ @dateDebTrt +''',121), CONVERT(DATETIME, '''+ @dateFinTrt +''',121))';
			EXEC sp_executesql @SQLCommand
			CLOSE tables_cursor;
			DEALLOCATE tables_cursor;
			THROW;
			--RETURN;
		END CATCH;

		FETCH NEXT FROM tables_cursor INTO @sourceName, @targetName
	END

	CLOSE tables_cursor
	DEALLOCATE tables_cursor
END;
GO


