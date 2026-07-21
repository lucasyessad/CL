/* ================================================================
   DT-1374 - Generation des DDL des tables de traces (OIT / OWT)
   V2 - aligne sur la structure des VUES CDC EXPORTEES
        (cdc.ZBCP_LIGIS_<table>_V) :
     - ods.OIT_<table> reproduit EXACTEMENT la structure de la vue
       exportee, dans le meme ordre (BULK INSERT positionnel) :
         1. colonnes techniques CDC en tete :
            ID_INSTANCE_TEC, CD_SEQ_TEC, CD_CMD_TEC, DT_COMMIT_TEC
         2. colonnes metier de la table source (ordre column_id,
            hors CS% et calculees, comme la vue)
         3. FL_FIN_JOURNEE en fin (flag image fin de journee)
            -> voir NOTE BULK INSERT ci-dessous
     - dbo.OWT_<table> = colonnes metier + colonnes TEC (tracabilite
       de la trace retenue) + colonnes techniques DWH standard maison
       (DD_VAL, DF_VAL, FL_VER_CRT, NO_SEQ, DT_MAJ, CD_USR_MAJ,
       ID_TRT_ALI), PK = (PK source + DD_VAL), sans IDENTITY,
       index filtre FL_VER_CRT = 1.

   ORDRE "DERNIERE LIGNE MODIFIEE" (parametrage FL_ORDRE_TRI) :
     DT_COMMIT_TEC (1er = borne de fenetre) puis CD_SEQ_TEC (departage
     des modifications d'un meme commit).

   NOTE BULK INSERT : la vue exportee ne contient pas FL_FIN_JOURNEE.
   Pour garder TRUNCATE + BULK INSERT sans fichier de format, ajouter
   en DERNIERE colonne de la vue exportee :
        , CONVERT(bit, 0) AS FL_FIN_JOURNEE
   (une ligne dans votre generateur de vues, apres le STRING_AGG).
   Sinon : fichier de format BCP ou vue d'insertion cote INEO.
   ================================================================ */

IF EXISTS (SELECT 1 FROM tempdb.sys.tables WHERE name LIKE '##TableListODS%')
    DROP TABLE ##TableListODS;
GO

CREATE TABLE ##TableListODS (
    TableNameSource   sysname NOT NULL,
    TableNameCibleODS sysname NOT NULL,
    TableNameCibleDWH sysname NOT NULL,
    CreateScriptODS   nvarchar(MAX) NULL,
    CreateScriptDWH   nvarchar(MAX) NULL
);
GO

--  Perimetre : tables sous CDC (table d'audit cdc.TEC_AUD_CDC)
INSERT INTO ##TableListODS (TableNameSource, TableNameCibleODS, TableNameCibleDWH)
SELECT
    t.name              AS TableNameSource,
    'OIT_' + t.name     AS TableNameCibleODS,
    'OWT_' + t.name     AS TableNameCibleDWH
FROM sys.tables t
INNER JOIN sys.schemas s
    ON s.schema_id = t.schema_id
INNER JOIN [cdc].[TEC_AUD_CDC] tm
    ON tm.LB_INSTANCE = ('dbo_' + t.name)
ORDER BY t.name;

SET NOCOUNT ON;

DECLARE @SchemaSource   sysname = N'dbo';
DECLARE @SchemaCibleODS sysname = N'ods';   -- <<< schema cible ODS
DECLARE @SchemaCibleDWH sysname = N'dbo';   -- <<< schema cible DWH

/* ----------------------------------------------------------------
   COLONNES TECHNIQUES (listes ajustables)
   ---------------------------------------------------------------- */
-- En TETE de OIT (memes noms/ordre que la vue CDC exportee) :
DECLARE @TechColsCDC nvarchar(MAX) =
      N'[ID_INSTANCE_TEC] int NULL,' + CHAR(13) +
      N'        [CD_SEQ_TEC] varbinary(10) NULL,' + CHAR(13) +
      N'        [CD_CMD_TEC] int NULL,' + CHAR(13) +
      N'        [DT_COMMIT_TEC] datetime2(3) NULL';

-- En FIN de OIT :
DECLARE @TechColsODS nvarchar(MAX) = N'[FL_FIN_JOURNEE] bit NOT NULL DEFAULT (0)';

-- En FIN de OWT (tracabilite TEC + standard maison) :
DECLARE @TechColsDWH nvarchar(MAX) =
      N'[ID_INSTANCE_TEC] int NULL,' + CHAR(13) +
      N'        [CD_SEQ_TEC] varbinary(10) NULL,' + CHAR(13) +
      N'        [CD_CMD_TEC] int NULL,' + CHAR(13) +
      N'        [DT_COMMIT_TEC] datetime2(3) NULL,' + CHAR(13) +
      N'        [DD_VAL] date NOT NULL,' + CHAR(13) +
      N'        [DF_VAL] date NOT NULL DEFAULT (''2400-01-01''),' + CHAR(13) +
      N'        [FL_VER_CRT] bit NOT NULL DEFAULT (1),' + CHAR(13) +
      N'        [NO_SEQ] int NULL,' + CHAR(13) +
      N'        [DT_MAJ] datetime NULL DEFAULT (GETDATE()),' + CHAR(13) +
      N'        [CD_USR_MAJ] nvarchar(20) NULL,' + CHAR(13) +
      N'        [ID_TRT_ALI] int NULL';
-- NB : seules DD_VAL / DF_VAL / FL_VER_CRT sont alimentees par
-- ORT_PRC_SS_HISTORISATION_OWT ; les colonnes TEC de OWT le sont via le
-- mapping du parametrage (lignes LB_CHAMP_ODS -> LB_CHAMP_DWH).

DECLARE
    @TableNameSource   sysname,
    @TableNameCibleODS sysname,
    @TableNameCibleDWH sysname,
    @CreateODS         nvarchar(MAX),
    @CreateDWH         nvarchar(MAX),
    @PKSorted          nvarchar(MAX),
    @PKPlain           nvarchar(MAX),
    @IsClustered       bit;

DECLARE cur CURSOR FAST_FORWARD FOR
    SELECT TableNameSource, TableNameCibleODS, TableNameCibleDWH
    FROM ##TableListODS;

OPEN cur;
FETCH NEXT FROM cur INTO @TableNameSource, @TableNameCibleODS, @TableNameCibleDWH;

WHILE @@FETCH_STATUS = 0
BEGIN
    /* 1) Colonnes metier de la source (types exacts) */
    IF OBJECT_ID('tempdb..#cols') IS NOT NULL DROP TABLE #cols;

    SELECT
        c.column_id,
        ColumnName = QUOTENAME(c.name),
        TypeBase =
            CASE
                WHEN t.name IN ('varchar','char','varbinary','binary')
                    THEN t.name + '(' +
                         CASE WHEN c.max_length = -1 THEN 'MAX'
                              ELSE CAST(c.max_length AS varchar(10)) END + ')'
                WHEN t.name IN ('nvarchar','nchar')
                    THEN t.name + '(' +
                         CASE WHEN c.max_length <> -1 THEN CAST(c.max_length/2 AS varchar(10))
                              ELSE 'MAX' END + ')'
                WHEN t.name IN ('decimal','numeric')
                    THEN t.name + '(' + CAST(c.precision AS varchar(10)) + ',' + CAST(c.scale AS varchar(10)) + ')'
                WHEN t.name IN ('datetime2','time','datetimeoffset')
                    THEN t.name + '(' + CAST(c.scale AS varchar(10)) + ')'
                ELSE t.name
            END,
        DefaultClause =
            CASE WHEN dc.definition IS NOT NULL
                 THEN ' DEFAULT ' + dc.definition
                 ELSE '' END,
        NullClause =
            CASE WHEN c.is_nullable = 1 THEN ' NULL' ELSE ' NOT NULL' END
    INTO #cols
    FROM sys.tables tb
    JOIN sys.schemas s ON s.schema_id = tb.schema_id
    JOIN sys.columns c ON c.object_id = tb.object_id
    JOIN sys.types   t ON t.user_type_id = c.user_type_id
    LEFT JOIN sys.default_constraints dc
           ON dc.parent_object_id = tb.object_id AND dc.parent_column_id = c.column_id
    WHERE s.name = @SchemaSource
      AND tb.name = @TableNameSource
      AND c.is_computed = 0
      AND c.name NOT LIKE 'CS%';        -- colonnes techniques CDC source exclues (comme la vue)
    -- NB : IDENTITY volontairement NON reprise (ni OIT ni OWT) : les
    -- lignes arrivent par BULK INSERT / INSERT SELECT, une IDENTITY
    -- imposerait KEEPIDENTITY / IDENTITY_INSERT partout.

    /* 2) PK de la source (2 formats) */
    SELECT @PKSorted = NULL, @PKPlain = NULL, @IsClustered = NULL;

    SELECT
        @IsClustered = CASE WHEN idx.type = 1 THEN 1 ELSE 0 END,
        @PKSorted = STRING_AGG(QUOTENAME(c.name)
                        + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END,
                        ', ') WITHIN GROUP (ORDER BY ic.key_ordinal),
        @PKPlain  = STRING_AGG(QUOTENAME(c.name), ', ') WITHIN GROUP (ORDER BY ic.key_ordinal)
    FROM sys.tables tb
    JOIN sys.schemas s          ON s.schema_id = tb.schema_id
    JOIN sys.key_constraints kc ON kc.parent_object_id = tb.object_id
    JOIN sys.indexes idx        ON idx.object_id = kc.parent_object_id
                               AND idx.index_id  = kc.unique_index_id
    JOIN sys.index_columns ic   ON ic.object_id = idx.object_id
                               AND ic.index_id  = idx.index_id
    JOIN sys.columns c          ON c.object_id = ic.object_id
                               AND c.column_id = ic.column_id
    WHERE s.name = @SchemaSource
      AND tb.name = @TableNameSource
      AND kc.type = 'PK'
    GROUP BY idx.type;

    /* 3) Script ODS : ods.OIT_x = TEC en tete + metier + FL_FIN_JOURNEE
          SANS PK (traces multiples par cle) ; index cle + DT_COMMIT_TEC */
    SELECT @CreateODS =
        'IF OBJECT_ID(N''' + @SchemaCibleODS + '.' + @TableNameCibleODS + ''',''U'') IS NOT NULL DROP TABLE '
        + QUOTENAME(@SchemaCibleODS) + '.' + QUOTENAME(@TableNameCibleODS) + ';' + CHAR(13) + CHAR(13) +
        'CREATE TABLE ' + QUOTENAME(@SchemaCibleODS) + '.' + QUOTENAME(@TableNameCibleODS) + ' (' + CHAR(13) +
        '        ' + @TechColsCDC + ',' + CHAR(13) +
        '        ' +
        STRING_AGG(ColumnName + ' ' + TypeBase + DefaultClause + NullClause,
                   ',' + CHAR(13) + '        ') WITHIN GROUP (ORDER BY column_id) +
        ',' + CHAR(13) + '        ' + @TechColsODS + CHAR(13) +
        '    );'
        + CASE WHEN @PKPlain IS NOT NULL
               THEN CHAR(13) + 'CREATE NONCLUSTERED INDEX ' + QUOTENAME('IX_' + @TableNameCibleODS + '_CLE')
                    + ' ON ' + QUOTENAME(@SchemaCibleODS) + '.' + QUOTENAME(@TableNameCibleODS)
                    + ' (' + @PKPlain + ', [DT_COMMIT_TEC]);'
                    + CHAR(13) + '-- PK source non reprise : plusieurs traces par cle fonctionnelle.'
               ELSE CHAR(13) + 'CREATE NONCLUSTERED INDEX ' + QUOTENAME('IX_' + @TableNameCibleODS + '_COMMIT')
                    + ' ON ' + QUOTENAME(@SchemaCibleODS) + '.' + QUOTENAME(@TableNameCibleODS)
                    + ' ([DT_COMMIT_TEC]);' END
    FROM #cols;

    /* 4) Script DWH : dbo.OWT_x = metier + TEC (tracabilite) + tech DWH
          PK = (PK source + DD_VAL) ; index filtre versions courantes */
    SELECT @CreateDWH =
        'IF OBJECT_ID(N''' + @SchemaCibleDWH + '.' + @TableNameCibleDWH + ''',''U'') IS NOT NULL DROP TABLE '
        + QUOTENAME(@SchemaCibleDWH) + '.' + QUOTENAME(@TableNameCibleDWH) + ';' + CHAR(13) + CHAR(13) +
        'CREATE TABLE ' + QUOTENAME(@SchemaCibleDWH) + '.' + QUOTENAME(@TableNameCibleDWH) + ' (' + CHAR(13) +
        '        ' +
        STRING_AGG(ColumnName + ' ' + TypeBase + DefaultClause + NullClause,
                   ',' + CHAR(13) + '        ') WITHIN GROUP (ORDER BY column_id) +
        ',' + CHAR(13) + '        ' + @TechColsDWH +
        CASE WHEN @PKSorted IS NOT NULL
             THEN ',' + CHAR(13) + '        CONSTRAINT ' + QUOTENAME('PK_' + @TableNameCibleDWH)
                  + ' PRIMARY KEY ' + CASE WHEN @IsClustered = 1 THEN 'CLUSTERED ' ELSE 'NONCLUSTERED ' END
                  + '(' + @PKSorted + ', [DD_VAL] ASC)'
             ELSE '' END
        + CHAR(13) + '    );'
        + CASE WHEN @PKPlain IS NOT NULL
               THEN CHAR(13) + 'CREATE NONCLUSTERED INDEX ' + QUOTENAME('IX_' + @TableNameCibleDWH + '_VER_CRT')
                    + ' ON ' + QUOTENAME(@SchemaCibleDWH) + '.' + QUOTENAME(@TableNameCibleDWH)
                    + ' (' + @PKPlain + ') WHERE [FL_VER_CRT] = 1;'
               ELSE '' END
    FROM #cols;

    /* 5) Mise a jour dans la table de correspondance */
    UPDATE ##TableListODS
       SET CreateScriptODS = @CreateODS,
           CreateScriptDWH = @CreateDWH
     WHERE TableNameSource = @TableNameSource;

    /* ==============================================================
       OPTION A : EXECUTER LES SCRIPTS IMMEDIATEMENT
       ==============================================================
     PRINT 'Execution ODS : ' + @TableNameCibleODS;  EXEC(@CreateODS);
     PRINT 'Execution DWH : ' + @TableNameCibleDWH;  EXEC(@CreateDWH); */

    FETCH NEXT FROM cur INTO @TableNameSource, @TableNameCibleODS, @TableNameCibleDWH;
END

CLOSE cur;
DEALLOCATE cur;
GO

/* Verification */
SELECT * FROM ##TableListODS;
