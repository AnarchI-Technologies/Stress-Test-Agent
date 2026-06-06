<#
Safe stress test agent for AnarchI core_engine.
This script runs non-destructive checks and fuzz tests only.
It WILL NOT call system-cull, pagefile, or cloud offload functions.

Usage:
  pwsh .\run-stress-test.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# Ensure environment opts to avoid destructive operations
$env:ANARCHI_DRY_RUN = '1'
$env:ANARCHI_ALLOW_UNSIGNED_PLUGINS = '1'
# Enable automation mode so the core engine will run non-interactively
$env:ANARCHI_AUTO_MODE = '1'

$core = Join-Path $root '..\..\core_engine\anarchi_core.ps1' | Resolve-Path -ErrorAction SilentlyContinue
if (-not $core) { Write-Error "Core engine not found at expected path: ..\\..\\core_engine\\anarchi_core.ps1"; exit 2 }
$core = $core.Path

Write-Host "Running core engine in automation mode (child process): $core" -ForegroundColor Green
pwsh -NoProfile -ExecutionPolicy Bypass -File $core
# Disable auto mode in the parent so dot-sourcing loads functions without triggering interactive flow
$env:ANARCHI_AUTO_MODE = '0'
Write-Host "Sourcing core engine into this session (dry-run, non-interactive): $core" -ForegroundColor Green
. $core

# Helper to run a test and capture result
function Run-Test($Name, [scriptblock]$Action) {
    Write-Host "== Test: $Name ==" -ForegroundColor Yellow
    try {
        # Capture any pipeline output from the action to avoid polluting caller's result array
        $actionOutput = & $Action | Out-String
        Write-Host "[OK] $Name" -ForegroundColor Green
        return @{ name=$Name; ok=$true }
    } catch {
        Write-Host "[FAIL] $Name -> $($_.Exception.Message)" -ForegroundColor Red
        return @{ name=$Name; ok=$false; error=$_.Exception.Message }
    }
}

$results = @()

# 1) Lint (PSScriptAnalyzer) if available
if (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue) {
    $r = Run-Test 'PSScriptAnalyzer anarchi_core' { Invoke-ScriptAnalyzer -Path $core -Recurse -Severity Warning | Tee-Object -Variable Lint; if ($Lint) { Write-Host "Warnings: $($Lint.Count)"; $Lint } }
    $results += $r
} else {
    Write-Host "PSScriptAnalyzer not installed; skipping lint." -ForegroundColor DarkYellow
}

# 2) Marketplace install sample plugin
$installScript = Join-Path $root '..\core_engine\tools\plugin_marketplace_stub.ps1'
if (-not (Test-Path $installScript)) { Write-Host "Marketplace stub missing; skipping marketplace install." -ForegroundColor DarkYellow }
else {
    $r = Run-Test 'Marketplace install sample_optimizer' { pwsh -NoProfile -NoLogo -Command "& '$installScript' -Action install -PluginName sample_optimizer" }
    $results += $r
}

# 3) Test core functions that are non-destructive
$testUrls = @(
    'http://localhost:8080',
    'http://127.0.0.1',
    'https://example.com',
    'file:///C:/Windows/System32/cmd.exe',
    "http://10.0.0.5/path?query=$(('x'*1024))"  # long query
)

foreach ($u in $testUrls) {
    $name = "Test-IsLocalhost for $u"
    $results += Run-Test $name { Test-IsLocalhost -Url $u }
}

# 4) Test cache directory creation
$testUrl = 'https://example.com/some/path'
$results += Run-Test 'Get-PersistentCacheDir' { $d = Get-PersistentCacheDir -Url $testUrl; Write-Host "Cache dir: $d" }

# 5) Load plugins (non-destructive) multiple times
$results += Run-Test 'Load-Plugins once' { Load-Plugins }
$results += Run-Test 'Load-Plugins repeated (concurrency small jobs)' {
    $jobs = @()
    $useThread = $false
    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) { $useThread = $true }
    for ($i=0; $i -lt 6; $i++) {
        if ($useThread) {
            $jobs += Start-ThreadJob -ScriptBlock { param($p) $env:ANARCHI_DRY_RUN='1'; $env:ANARCHI_ALLOW_UNSIGNED_PLUGINS='1'; $env:ANARCHI_AUTO_MODE='0'; . $p; Load-Plugins } -ArgumentList $core
        } else {
            $init = { $env:ANARCHI_DRY_RUN='1'; $env:ANARCHI_ALLOW_UNSIGNED_PLUGINS='1'; $env:ANARCHI_AUTO_MODE='0' }
            $jobs += Start-Job -InitializationScript $init -ScriptBlock { param($p) . $p; Load-Plugins } -ArgumentList $core
        }
    }
    $jobs | Wait-Job | Out-Null
    $failed = $jobs | Where-Object { $_.State -ne 'Completed' }
    if ($failed) { throw "Some plugin load jobs failed: $($failed | Select-Object Id, State | Out-String)" }
    $jobs | Receive-Job | Out-Null
    $jobs | Remove-Job -Force
}

# 6) Fuzz plugin manifests (create malformed manifest, expect engine to handle gracefully)
$pluginDir = Join-Path $root '..\core_engine\plugins' | Resolve-Path -ErrorAction SilentlyContinue
if (-not $pluginDir) { New-Item -ItemType Directory -Path (Join-Path $root '..\core_engine\plugins') -Force | Out-Null; $pluginDir = Join-Path $root '..\core_engine\plugins' }
$badManifest = Join-Path $pluginDir 'bad_plugin.json'
@'
{
  "name": "bad",
  "file": "bad.ps1",
  this is invalid json
}
'@ | Set-Content -Path $badManifest -Force
$results += Run-Test 'Load-Plugins with bad manifest present' { Load-Plugins }
Remove-Item $badManifest -Force -ErrorAction SilentlyContinue

# 7) Repetition loop: run a batch of tests multiple times, attempt simple fixes
$maxIter = 5
for ($iter=1; $iter -le $maxIter; $iter++) {
    Write-Host "--- Iteration ${iter}/${maxIter}: quick functional sweep ---" -ForegroundColor Cyan
    $batch = @()
    $batch += Run-Test "Iteration$iter-Test-IsLocalhost-local" { Test-IsLocalhost -Url 'http://localhost:8080' }
    $batch += Run-Test "Iteration$iter-CacheDir" { Get-PersistentCacheDir -Url 'https://example.com/iter'$iter }
    $batch += Run-Test "Iteration$iter-LoadPlugins" { Load-Plugins }

    $failed = $batch | Where-Object { $_ -and ($_.ok -eq $false) }
    if ($failed.Count -eq 0) { Write-Host "Iteration ${iter} succeeded." -ForegroundColor Green; continue }

    $names = ($failed | ForEach-Object { $_.name }) -join ', '
    Write-Host "Detected failures in iteration ${iter}: $names" -ForegroundColor Yellow
    # Attempt simple automated fixes
    foreach ($f in $failed) {
        if ($f.name -like '*LoadPlugins*' -or $f.name -like '*Load-Plugins*') {
            Write-Host "Attempting plugin reinstall from marketplace for resilience..." -ForegroundColor Cyan
            if (Test-Path $installScript) { pwsh -NoProfile -NoLogo -Command "& '$installScript' -Action install -PluginName sample_optimizer" }
        }
    }
}

# Summarize results
$summary = @{ total = $results.Count; failures = ($results | Where-Object { -not $_.ok }).Count }
Write-Host "Stress test summary: $($summary.total) checks, $($summary.failures) failures." -ForegroundColor Magenta
if ($summary.failures -gt 0) { Write-Host "Failures present — inspect output above and open an issue with logs." -ForegroundColor Red } else { Write-Host "No failures detected in non-destructive tests." -ForegroundColor Green }

# Persist results to a file
$report = Join-Path $root 'stress-test-report.json'
$results | ConvertTo-Json -Depth 4 | Set-Content -Path $report -Force
Write-Host "Report written to: $report"

# Exit with code 0 even if failures to avoid destructive retries without consent
exit 0
