USE [DWH_CL_ESTIM]
GO

/****** Object:  StoredProcedure [dbo].[PS_CHARGEMENT_ODS_DWH]    Script Date: 21/07/2026 09:53:56 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[PS_CHARGEMENT_ODS_DWH]
	@par_ID_TRT_ALI NVARCHAR(20),
	@par_projectName NVARCHAR(50)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE
		@dateMAJ		NVARCHAR(30) = CONVERT(NVARCHAR(30), GETDATE(), 121),
		@dateDeb		NVARCHAR(50) = N'CONVERT(DATE,''1900-01-01'')',
		@dateFin		NVARCHAR(50) = N'CONVERT(DATE,''2400-01-01'')',
		@userMAJ		NVARCHAR(20) = N'SUPERVIS',
		@ID_TRT_ALI		NVARCHAR(20) = @par_ID_TRT_ALI,
		@projectName	NVARCHAR(50) = @par_projectName,
		@sourceName		NVARCHAR(50),
		@targetName		NVARCHAR(50),
		@SCDType		NVARCHAR(20),
		@insertValues	NVARCHAR(MAX),
		@insertColumns	NVARCHAR(MAX),
		@keyCondition	NVARCHAR(MAX),
		@valueCondition	NVARCHAR(MAX),
		@dateDebTrt		NVARCHAR(30),
		@dateFinTrt		NVARCHAR(30),
		@rowCount		INT,
		@SQLCommand		NVARCHAR(MAX);

	-- Curseur pour parcourir la liste des tables
	DECLARE tables_cursor CURSOR FOR
		SELECT [LB_TABLE_ODS], [LB_TABLE_DWH], [LB_SCD]
		FROM [ods].[PARAM_CHARGEMENT]
		WHERE [LB_PROJET] = @projectName
		  AND [NO_CHAMP]  = 1
		  AND [FL_CHARGEMENT] = 1;

	OPEN tables_cursor;
	FETCH NEXT FROM tables_cursor INTO @sourceName, @targetName, @SCDType;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		BEGIN TRY
			---------------------------------
			-- 1) Champs SOURCE (liste de valeurs pour INSERT)
			---------------------------------
			SELECT @insertValues =
				STRING_AGG(
					CAST(N'S.' + QUOTENAME([LB_CHAMP_ODS]) AS NVARCHAR(MAX)),
					N', '
				) WITHIN GROUP (ORDER BY [NO_CHAMP])
			FROM [ods].[PARAM_CHARGEMENT]
			WHERE [LB_PROJET]  = @projectName
			  AND [LB_TABLE_ODS] = @sourceName
			  AND [LB_CHAMP_ODS] IS NOT NULL
			GROUP BY [LB_TABLE_ODS];

			---------------------------------
			-- 2) Champs CIBLE (liste de colonnes pour INSERT)
			---------------------------------
			SELECT @insertColumns =
				STRING_AGG(
					CAST(QUOTENAME([LB_CHAMP_DWH]) AS NVARCHAR(MAX)),
					N', '
				) WITHIN GROUP (ORDER BY [NO_CHAMP])
			FROM [ods].[PARAM_CHARGEMENT]
			WHERE [LB_PROJET]   = @projectName
			  AND [LB_TABLE_DWH] = @targetName
			GROUP BY [LB_TABLE_DWH];

			---------------------------------
			-- 3) Clé de correspondance (JOIN/MERGE)
			---------------------------------
			SELECT @keyCondition =
				STRING_AGG(
					CAST(N'S.' + QUOTENAME([LB_CHAMP_ODS]) + N' = T.' + QUOTENAME([LB_CHAMP_DWH]) AS NVARCHAR(MAX)),
					N' AND '
				)
			FROM [ods].[PARAM_CHARGEMENT]
			WHERE [LB_PROJET]	= @projectName
			  AND [LB_TABLE_ODS]  = @sourceName
			  AND [LB_TABLE_DWH]  = @targetName
			  AND [FL_CLEF]	   = 1;

			---------------------------------
			-- 4) Condition de comparaison null-safe (différence)
			---------------------------------
			SELECT @valueCondition =
				STRING_AGG(
					CAST(
						N'(S.' + QUOTENAME([LB_CHAMP_ODS]) + N' <> T.' + QUOTENAME([LB_CHAMP_DWH]) +
						N' AND S.' + QUOTENAME([LB_CHAMP_ODS]) + N' IS NOT NULL AND T.' + QUOTENAME([LB_CHAMP_DWH]) + N' IS NOT NULL)
						  OR (S.' + QUOTENAME([LB_CHAMP_ODS]) + N' IS NULL AND T.' + QUOTENAME([LB_CHAMP_DWH]) + N' IS NOT NULL)
						  OR (S.' + QUOTENAME([LB_CHAMP_ODS]) + N' IS NOT NULL AND T.' + QUOTENAME([LB_CHAMP_DWH]) + N' IS NULL)'
						AS NVARCHAR(MAX)
					),
					NCHAR(13) + NCHAR(10) + N' OR '
				)
			FROM [ods].[PARAM_CHARGEMENT]
			WHERE [LB_PROJET]	= @projectName
			  AND [LB_TABLE_ODS]  = @sourceName
			  AND [LB_TABLE_DWH]  = @targetName
			  AND [LB_CHAMP_ODS] IS NOT NULL
			  AND [FL_CLEF]	   = 0;

			---------------------------------
			-- Intégration selon le type SCD
			---------------------------------
			PRINT N'*************************************************';
			PRINT N'Intégration : ' + @sourceName + N' -> ' + @targetName;
			PRINT N'Clé : ' + @keyCondition;

			-- TYPE INSERT ON CHANGE
			IF @SCDType = N'INSERT ON CHANGE'
			BEGIN
				PRINT N'SCD INSERT ON CHANGE';

				SET @SQLCommand = N'
MERGE INTO [dbo].' + QUOTENAME(@targetName) + N' AS T
USING [ods].' + QUOTENAME(@sourceName) + N' AS S
ON (' + @keyCondition + N')
WHEN NOT MATCHED BY TARGET THEN
	INSERT (' + @insertColumns + N')
	VALUES (' + @insertValues + N', ' + @dateDeb + N', ' + @dateFin + N', 1, 1, CONVERT(DATETIME, N''' + @dateMAJ + N''', 121), N''' + @userMAJ + N''', ' + @ID_TRT_ALI + N');
SET @rowCount = @@ROWCOUNT;';
			END

			-- TYPE 1
			ELSE IF @SCDType = N'TYPE 1'
			BEGIN
				PRINT N'SCD Type 1';

				SET @SQLCommand = N'
TRUNCATE TABLE [dbo].' + QUOTENAME(@targetName) + N';
INSERT INTO [dbo].' + QUOTENAME(@targetName) + N' (' + @insertColumns + N')
SELECT ' + @insertValues + N', ' + @dateDeb + N', ' + @dateFin + N', 1, 1, CONVERT(DATETIME, N''' + @dateMAJ + N''', 121), N''' + @userMAJ + N''', ' + @ID_TRT_ALI + N'
FROM [ods].' + QUOTENAME(@sourceName) + N' AS S;
SET @rowCount = @@ROWCOUNT;';
			END

			-- TYPE 2
			ELSE IF @SCDType = N'TYPE 2'
			BEGIN
				PRINT N'SCD Type 2';

				SET @SQLCommand = N'
SET @rowCount = 0;

MERGE INTO [dbo].' + QUOTENAME(@targetName) + N' AS T
USING [ods].' + QUOTENAME(@sourceName) + N' AS S
ON (' + @keyCondition + N' AND T.[FL_VER_CRT] = 1)

WHEN MATCHED AND (
' + @valueCondition + N'
) THEN
	UPDATE SET
		T.[FL_VER_CRT] = 0,
		T.[DF_VAL]	 = CONVERT(DATETIME, N''' + @dateMAJ + N''', 121),
		T.[DT_MAJ]	 = CONVERT(DATETIME, N''' + @dateMAJ + N''', 121),
		T.[CD_USR_MAJ] = N''' + @userMAJ + N''',
		T.[ID_TRT_ALI] = ' + @ID_TRT_ALI + N'

WHEN NOT MATCHED BY TARGET THEN
	INSERT (' + @insertColumns + N')
	VALUES (' + @insertValues + N', ' + @dateDeb + N', ' + @dateFin + N', 1, 1, CONVERT(DATETIME, N''' + @dateMAJ + N''', 121), N''' + @userMAJ + N''', ' + @ID_TRT_ALI + N');

SET @rowCount += @@ROWCOUNT;

INSERT INTO [dbo].' + QUOTENAME(@targetName) + N' (' + @insertColumns + N')
SELECT ' + @insertValues + N', CONVERT(DATETIME, N''' + @dateMAJ + N''', 121), ' + @dateFin + N', T.NO_SEQ + 1, 1, CONVERT(DATETIME, N''' + @dateMAJ + N''', 121), N''' + @userMAJ + N''', ' + @ID_TRT_ALI + N'
FROM [ods].' + QUOTENAME(@sourceName) + N' AS S
INNER JOIN [dbo].' + QUOTENAME(@targetName) + N' AS T
	ON (' + @keyCondition + N')
WHERE T.[FL_VER_CRT] = 0
  AND T.[DF_VAL] = CONVERT(DATETIME, N''' + @dateMAJ + N''', 121);

SET @rowCount += @@ROWCOUNT;';
				PRINT N'Champs comparés : ' + @valueCondition;
				-- PRINT @SQLCommand; -- (facultatif; tronque au-delà de ~4000)
			END

			-- Exécution du SQL dynamique
			SET @dateDebTrt = CONVERT(NVARCHAR(30), GETDATE(), 121);
			EXEC sp_executesql @SQLCommand, N'@rowCount INT OUTPUT', @rowCount = @rowCount OUTPUT;

			PRINT N'Nombre de lignes : ' + CAST(@rowCount AS NVARCHAR(30));
			SET @dateFinTrt = CONVERT(NVARCHAR(30), GETDATE(), 121);

			-- AUDIT (OK)
			SET @SQLCommand = N'
INSERT INTO [ods].[AUDIT_CHARGEMENT]
VALUES (' + @ID_TRT_ALI + N', N''' + @projectName + N''',
		N''Chargement ods -> dwh'', N''' + @sourceName + N''', N''' + @targetName + N''',
		' + CAST(@rowCount AS NVARCHAR(30)) + N', N''OK'', NULL,
		CONVERT(DATETIME, N''' + @dateDebTrt + N''', 121),
		CONVERT(DATETIME, N''' + @dateFinTrt + N''', 121));';

			EXEC sp_executesql @SQLCommand;
		END TRY
		BEGIN CATCH
			-- AUDIT (KO)
			SET @dateFinTrt = CONVERT(NVARCHAR(30), GETDATE(), 121);
			SET @SQLCommand = N'
INSERT INTO [ods].[AUDIT_CHARGEMENT]
VALUES (' + @ID_TRT_ALI + N', N''' + @projectName + N''',
		N''Chargement ods -> dwh'', N''' + @sourceName + N''', N''' + @targetName + N''',
		0, N''KO'', ERROR_MESSAGE(),
		CONVERT(DATETIME, N''' + @dateDebTrt + N''', 121),
		CONVERT(DATETIME, N''' + @dateFinTrt + N''', 121));';
			EXEC sp_executesql @SQLCommand;
			PRINT @SQLCommand;

			CLOSE tables_cursor;
			DEALLOCATE tables_cursor;
			THROW;
		END CATCH;

		FETCH NEXT FROM tables_cursor INTO @sourceName, @targetName, @SCDType;
	END

	CLOSE tables_cursor;
	DEALLOCATE tables_cursor;
END;
GO

