# NOTE: このファイルは必ずUTF-8(BOM付き)で保存すること。Windows PowerShell 5.1はBOM無しをANSIとして解釈し、日本語が文字化けして構文エラーになる。
# =====================================================================
# Stop hook: 品質ゲート未実行の注意喚起
#
# 未コミットの変更がある領域(frontend/backend/terraform)について、
# 最終変更より後に品質ゲートの完了コマンドが実行されていなければ
# 停止をブロックして注意喚起する(exit 2)。
# 無限ループ防止のため stop_hook_active のときは常に通す。
# =====================================================================
$ErrorActionPreference = "SilentlyContinue"

$inputJson = [Console]::In.ReadToEnd()
try {
    $payload = $inputJson | ConvertFrom-Json
} catch {
    exit 0
}

# Stop hookからの継続中は再ブロックしない(無限ループ防止)
if ($payload.stop_hook_active -eq $true) { exit 0 }

$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) { $projectDir = $payload.cwd }
if (-not $projectDir -or -not (Test-Path $projectDir)) { exit 0 }
Set-Location $projectDir

$stateDir = Join-Path $projectDir ".claude\.state"

$changedFiles = (& git status --porcelain 2>$null | Out-String) -split "`n" | Where-Object { $_.Trim() }
if (-not $changedFiles) { exit 0 }

$pendingAreas = @()
foreach ($area in @("frontend", "backend", "terraform")) {
    $areaChanged = $changedFiles | Where-Object { $_.Substring(3) -like "$area/*" }
    if (-not $areaChanged) { continue }

    $stampFile = Join-Path $stateDir "gate-run-$area.txt"
    if (-not (Test-Path $stampFile)) {
        $pendingAreas += $area
        continue
    }

    $gateRunAt = [datetime]::Parse((Get-Content $stampFile -Raw).Trim())
    $latestChange = [datetime]::MinValue
    foreach ($line in $areaChanged) {
        $path = $line.Substring(3).Trim()
        if (Test-Path $path) {
            $mtime = (Get-Item $path).LastWriteTime
            if ($mtime -gt $latestChange) { $latestChange = $mtime }
        }
    }
    if ($latestChange -gt $gateRunAt) { $pendingAreas += $area }
}

if ($pendingAreas.Count -gt 0) {
    $areas = $pendingAreas -join ", "
    [Console]::Error.WriteLine("品質ゲート未実行の変更があります: $areas")
    [Console]::Error.WriteLine("完了報告の前に、該当領域の verify(/verify-all)を実行してください。実行不要な理由がある場合はその旨を報告に含めてください。")
    exit 2
}

exit 0
