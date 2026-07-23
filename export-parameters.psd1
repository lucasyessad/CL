@{
    SourceServer = "ASM"
    SourceDatabase = "Ligis5_Test_Data"
    SourceSchema = "cdc"
    SourceOutputDir = "\\sion\dsi\datalib"
    SourceViewSchema = "cdc"
    SourceViewNamePattern = "ZBCP[_]LIGIS[_]%[_]V"
    SourceViewPriorityName = "ZBCP_LIGIS_TEC_AUD_CDC_V"
    TargetCopyDir = "\\kenya\dsi\datalib"
    SourceCopyDir = "\\sion\dsi\datalib"
    CopyFilePattern = "*.bcp"
    CopyBatchFile = "copy_proc.bat"
    ListFileName = "tables-to-load.txt"
}