# ops-shell.ps1
#
# Switches this administrator PowerShell window to the AWS role keirekipro-ops
# for 900 seconds after the owner types the 6-digit code of the authenticator app.
#
# - The keys are kept only in the environment variables of this process.
#   This script never writes them to a file.
# - The script does not read settings that Claude can write: it clears the AWS,
#   proxy and Python environment variables, limits PATH to four folders, and
#   uses the AWS CLI config files in C:\Program Files\KeirekiPro (admin only).
# - Type ops-renew to enter a new code when the keys have expired (ExpiredToken).
#
# The owner places this file, aws-config and an empty empty-credentials file in
# C:\Program Files\KeirekiPro and starts it from the Start menu item
# "KeirekiPro ops" with "Run as administrator":
#   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "C:\Program Files\KeirekiPro\ops-shell.ps1"
#
# This file must stay ASCII only: Windows PowerShell 5.1 on Japanese Windows
# reads a UTF-8 file without BOM as Shift_JIS.

$script:OpsBaseDir = 'C:\Program Files\KeirekiPro'
$script:OpsAwsExe = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'
$script:OpsRoleArn = 'arn:aws:iam::<ACCOUNT_ID>:role/keirekipro-ops'
$script:OpsMfaArn = 'arn:aws:iam::<ACCOUNT_ID>:mfa/authenticator-app'
$script:OpsRegion = 'ap-northeast-1'
$script:OpsDurationSeconds = 900

# Step 1: true when this process runs as an administrator (elevated).
function Test-OpsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Step 2: remove the environment variables that can change how the AWS CLI
# finds keys, settings, proxies, certificates and Python code.
function Clear-OpsEnvironment {
    $exactNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
        'REQUESTS_CA_BUNDLE', 'SSL_CERT_FILE', 'CURL_CA_BUNDLE')
    $names = [Environment]::GetEnvironmentVariables('Process').Keys
    foreach ($name in @($names)) {
        $upper = ([string]$name).ToUpperInvariant()
        if ($upper.StartsWith('AWS_') -or $upper.StartsWith('PYTHON') -or ($exactNames -contains $upper)) {
            [Environment]::SetEnvironmentVariable([string]$name, $null, 'Process')
        }
    }
}

# Step 3: the only four folders in PATH.
function Get-OpsPathValue {
    $systemRoot = $env:SystemRoot
    $folders = @(
        (Join-Path $systemRoot 'System32'),
        $systemRoot,
        (Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0'),
        'C:\Program Files\Amazon\AWSCLIV2'
    )
    return ($folders -join ';')
}

# Steps 2 to 4.
function Initialize-OpsEnvironment {
    Clear-OpsEnvironment
    $env:PATH = Get-OpsPathValue
    $env:AWS_CONFIG_FILE = Join-Path $script:OpsBaseDir 'aws-config'
    $env:AWS_SHARED_CREDENTIALS_FILE = Join-Path $script:OpsBaseDir 'empty-credentials'
}

# Step 6: read the code without showing it on the screen.
function Read-OpsTokenCode {
    $secure = Read-Host -Prompt 'Enter the 6-digit code from the authenticator app' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Test-OpsTokenCode([string]$TokenCode) {
    return ($TokenCode -match '^[0-9]{6}$')
}

function New-OpsSessionName {
    return ('ops-' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
}

# Step 7: the arguments of aws sts assume-role.
function Get-OpsAssumeRoleArguments([string]$TokenCode, [string]$SessionName) {
    $parts = @(
        'sts', 'assume-role',
        '--profile', 'source',
        '--role-arn', $script:OpsRoleArn,
        '--role-session-name', $SessionName,
        '--serial-number', $script:OpsMfaArn,
        '--token-code', $TokenCode,
        '--duration-seconds', [string]$script:OpsDurationSeconds,
        '--output', 'json',
        '--no-cli-pager'
    )
    return ($parts -join ' ')
}

# Step 7: run aws.exe by its absolute path. The output is read through pipes,
# not files. The keys already in this process are not passed to aws.exe, so
# assume-role always starts from the source profile.
function Invoke-OpsAssumeRole([string]$TokenCode, [string]$FilePath = $script:OpsAwsExe) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = Get-OpsAssumeRoleArguments -TokenCode $TokenCode -SessionName (New-OpsSessionName)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = (Get-Location).ProviderPath
    foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN')) {
        if ($startInfo.EnvironmentVariables.ContainsKey($name)) {
            $startInfo.EnvironmentVariables.Remove($name)
        }
    }
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
    }
    catch {
        return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = ('Could not start ' + $FilePath + ': ' + $_.Exception.Message) }
    }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    $stderr = $stderrTask.Result
    return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

# True when the error comes from the expired or missing aws login session
# (messages of the Login errors in botocore exceptions.py of the AWS CLI).
function Test-OpsLoginExpired([string]$ErrorText) {
    return ($ErrorText -match "(?i)aws login|login session")
}

# Step 8: put the keys of the assume-role answer in the environment variables
# of this process and show when they expire.
function Set-OpsCredentials([string]$Json) {
    $answer = $Json | ConvertFrom-Json
    $credentials = $answer.Credentials
    if ($null -eq $credentials -or -not $credentials.AccessKeyId -or -not $credentials.SecretAccessKey -or -not $credentials.SessionToken) {
        throw 'The answer of assume-role has no credentials.'
    }
    $expiration = $credentials.Expiration
    if ($expiration -is [DateTime]) {
        $expiresAt = ([DateTimeOffset]$expiration).ToLocalTime()
    }
    else {
        $expiresAt = [DateTimeOffset]::Parse([string]$expiration, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
    }
    $env:AWS_ACCESS_KEY_ID = $credentials.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $credentials.SecretAccessKey
    $env:AWS_SESSION_TOKEN = $credentials.SessionToken
    $env:AWS_REGION = $script:OpsRegion
    return $expiresAt
}

# Steps 7 and 8 after aws.exe has finished. Returns true when the keys are set.
function Complete-OpsAssumeRole($Result) {
    if ($Result.ExitCode -ne 0) {
        Write-Host ('aws sts assume-role failed (exit code ' + $Result.ExitCode + '):') -ForegroundColor Red
        Write-Host $Result.StdErr
        if (Test-OpsLoginExpired $Result.StdErr) {
            Write-Host "The aws login session has expired. Run 'aws login' in your normal terminal, then type ops-renew here." -ForegroundColor Yellow
        }
        else {
            Write-Host 'No keys were set. Type ops-renew to enter the code again.' -ForegroundColor Yellow
        }
        return $false
    }
    try {
        $expiresAt = Set-OpsCredentials -Json $Result.StdOut
    }
    catch {
        Write-Host ('Could not read the answer of assume-role: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'No keys were set. Type ops-renew to enter the code again.' -ForegroundColor Yellow
        return $false
    }
    Write-Host ('This window now uses the role keirekipro-ops in ' + $script:OpsRegion + '.') -ForegroundColor Green
    Write-Host ('The keys expire at ' + $expiresAt.ToString('yyyy-MM-dd HH:mm:ss') + ' (local time). After that, type ops-renew.') -ForegroundColor Green
    return $true
}

# Step 9: enter a new code and switch to keirekipro-ops again.
function ops-renew {
    $code = Read-OpsTokenCode
    if (-not (Test-OpsTokenCode $code)) {
        Write-Host 'The code must be 6 digits. No keys were set. Type ops-renew to try again.' -ForegroundColor Yellow
        return
    }
    $result = Invoke-OpsAssumeRole -TokenCode $code
    $code = $null
    $null = Complete-OpsAssumeRole -Result $result
}

function Start-OpsShell {
    if (-not (Test-OpsAdministrator)) {
        Write-Host 'ops-shell must run as an administrator. Open the Start menu item "KeirekiPro ops" with "Run as administrator".' -ForegroundColor Red
        $null = Read-Host -Prompt 'Press Enter to close this window'
        [Environment]::Exit(1)
    }
    Initialize-OpsEnvironment
    Set-Location -LiteralPath $script:OpsBaseDir
    Write-Host 'KeirekiPro ops: switching to the role keirekipro-ops for 15 minutes.'
    ops-renew
}

# Run only when started as a script, not when dot-sourced (for tests).
if ($MyInvocation.InvocationName -ne '.') {
    Start-OpsShell
}
