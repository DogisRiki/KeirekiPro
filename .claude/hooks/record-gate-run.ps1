# NOTE: このファイルは必ずUTF-8(BOM付き)で保存すること。Windows PowerShell 5.1はBOM無しをANSIとして解釈し、日本語が文字化けして構文エラーになる。
# =====================================================================
# PostToolUse(Bash) hook: 品質ゲート実行の記録
#
# 品質ゲートコマンドの実行を領域別に記録する(Stop hookの検知材料)。
# 状態は .claude/.state/ 配下(gitignore済み)に保存する。
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

$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) { $projectDir = $payload.cwd }
if (-not $projectDir) { exit 0 }

$stateDir = Join-Path $projectDir ".claude\.state"
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }

$area = $null
if ($command -match 'frontend pnpm run coverage') { $area = "frontend" }
elseif ($command -match 'backend \./gradlew check') { $area = "backend" }
elseif ($command -match 'terraform checkov') { $area = "terraform" }

if ($area) {
    $stamp = (Get-Date).ToString("o")
    Set-Content -Path (Join-Path $stateDir "gate-run-$area.txt") -Value $stamp -Encoding utf8
}

exit 0
