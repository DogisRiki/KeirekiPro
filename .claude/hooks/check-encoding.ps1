# NOTE: このファイルは必ずUTF-8(BOM付き)で保存すること。Windows PowerShell 5.1はBOM無しをANSIとして解釈し、日本語が文字化けして構文エラーになる。
# =====================================================================
# PostToolUse(Edit|Write) hook: UTF-8文字化け検知
#
# 書き込まれたテキストファイルに不正なUTF-8バイト列、または
# 置換文字(U+FFFD)が含まれる場合にブロックする(exit 2)。
# 日本語×Windows環境での文字化けの機械的検知。
# =====================================================================
$ErrorActionPreference = "SilentlyContinue"

$inputJson = [Console]::In.ReadToEnd()
try {
    $payload = $inputJson | ConvertFrom-Json
} catch {
    exit 0
}

$filePath = $payload.tool_input.file_path
if (-not $filePath -or -not (Test-Path $filePath)) { exit 0 }

$textExtensions = @(
    ".ts", ".tsx", ".js", ".jsx", ".java", ".md", ".json", ".yaml", ".yml",
    ".sql", ".gradle", ".xml", ".html", ".css", ".sh", ".ps1", ".txt",
    ".pu", ".properties", ".toml", ".tf", ".tfvars", ".hcl", ".ftl", ".mjs", ".cjs"
)
$extension = [System.IO.Path]::GetExtension($filePath).ToLower()
if ($textExtensions -notcontains $extension) { exit 0 }

$bytes = [System.IO.File]::ReadAllBytes($filePath)
if ($bytes.Length -eq 0) { exit 0 }

try {
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $strictUtf8.GetString($bytes)
} catch {
    [Console]::Error.WriteLine("不正なUTF-8バイト列を検出しました: $filePath")
    [Console]::Error.WriteLine("文字化けした内容を保存しないでください。ファイルをUTF-8で書き直してください。判読できない場合は推測せず停止して報告してください。")
    exit 2
}

if ($text.Contains([char]0xFFFD)) {
    [Console]::Error.WriteLine("置換文字(U+FFFD)を検出しました: $filePath")
    [Console]::Error.WriteLine("文字化けの痕跡です。正しい日本語に修正してから保存してください。")
    exit 2
}

exit 0
