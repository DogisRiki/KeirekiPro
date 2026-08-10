# NOTE: このファイルは必ずUTF-8(BOM付き)で保存すること。Windows PowerShell 5.1はBOM無しをANSIとして解釈し、日本語が文字化けして構文エラーになる。
# =====================================================================
# PreToolUse(Bash) hook: mainブランチ保護
#
# mainブランチ上での git commit / git push、および強制pushを
# 実行前にブロックする(exit 2 = ブロック)。
# =====================================================================
$ErrorActionPreference = "SilentlyContinue"

$inputJson = [Console]::In.ReadToEnd()
try {
    $payload = $inputJson | ConvertFrom-Json
} catch {
    exit 0
}

$command = $payload.tool_input.command
if (-not $command) { exit 0 }

# 強制pushは常にブロック
if ($command -match 'git\s+push\b.*(\s--force(\s|$)|--force-with-lease|\s-f(\s|$))') {
    [Console]::Error.WriteLine("強制push(--force / -f)はブロックされています。履歴の書き換えが必要な場合は人間に相談してください。")
    exit 2
}

# git commit / git push はカレントブランチを確認
if ($command -match '(^|\s|&&|;)git\s+(commit|push)\b') {
    $cwd = $payload.cwd
    if ($cwd -and (Test-Path $cwd)) { Set-Location $cwd }
    $branch = (& git branch --show-current 2>$null | Out-String).Trim()
    if ($branch -eq "main") {
        [Console]::Error.WriteLine("mainブランチでのcommit/pushはブロックされています。.branch_name_template に従ってfeatureブランチを作成してください(例: git switch -c feat/xxx)。")
        exit 2
    }
    # mainへの直接push(他ブランチからの明示指定)もブロック
    if ($command -match 'git\s+push\s+\S+\s+.*\bmain\b') {
        [Console]::Error.WriteLine("mainブランチへの直接pushはブロックされています。featureブランチをpushしてPR経由でマージしてください。")
        exit 2
    }
}

exit 0
