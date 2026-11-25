[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-f]{40}$')]
  [string]$SourceSha,
  [string]$BuildRoot = 'C:\tmp'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$shortSha = $SourceSha.Substring(0, 8)
$worktree = Join-Path $BuildRoot "threads-harmony-build-$shortSha"
$buildProfile = Join-Path $worktree 'app\build-profile.json5'
$created = $false

if (-not (Test-Path -LiteralPath 'C:\DevEco Studio\tools\hvigor\bin\hvigorw.bat')) {
  throw 'DevEco Studio Hvigor was not found at the verified installation path.'
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
  throw 'Run this script from a Git worktree with a .git file/directory.'
}
if (Test-Path -LiteralPath $worktree) {
  throw "Refusing to overwrite existing build directory: $worktree"
}

try {
  & git -C $repoRoot worktree add --detach $worktree $SourceSha
  if ($LASTEXITCODE -ne 0) { throw "git worktree add failed with exit code $LASTEXITCODE" }
  $created = $true

  $actualSha = (& git -C $worktree rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $actualSha -ne $SourceSha) {
    throw "Worktree HEAD mismatch: expected $SourceSha, got $actualSha"
  }

  $text = [System.IO.File]::ReadAllText($buildProfile)
  $pattern = '(?m)^(\s*"compileSdkVersion"\s*:\s*)"26\.0\.0"(\s*,?)\r?$'
  $matches = [regex]::Matches($text, $pattern)
  if ($matches.Count -ne 1) {
    throw "Expected exactly one compileSdkVersion 26.0.0 line; found $($matches.Count). No automatic edit made."
  }
  $patched = [regex]::Replace($text, $pattern, '${1}"26.0.1"${2}', 1)
  [System.IO.File]::WriteAllText($buildProfile, $patched, [System.Text.UTF8Encoding]::new($false))

  $diff = (& git -C $worktree diff -- app/build-profile.json5 | Out-String)
  if ($LASTEXITCODE -ne 0 -or $diff -notmatch '^\+\s*"compileSdkVersion"\s*:\s*"26\.0\.1"' -or $diff -notmatch '^-\s*"compileSdkVersion"\s*:\s*"26\.0\.0"' -or $diff -match '^[+-](?![+-])(?!(\s*"compileSdkVersion"\s*:\s*"26\.0\.[01]"\s*,?\s*)$)' -and $diff -match '^[+-](?![+-])') {
    throw "Unexpected temporary build-profile diff:`n$diff"
  }

  Push-Location (Join-Path $worktree 'app')
  try {
    $env:DEVECO_SDK_HOME = 'C:\DevEco Studio\sdk'
    $env:NODE_HOME = 'C:\DevEco Studio\tools\node'
    $env:PATH = "$env:NODE_HOME;C:\DevEco Studio\tools\ohpm\bin;$env:PATH"
    & 'C:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' clean assembleHap --no-daemon -p product=default
    if ($LASTEXITCODE -ne 0) { throw "Hvigor failed with exit code $LASTEXITCODE" }
  }
  finally {
    Pop-Location
  }

  $hap = Join-Path $worktree 'app\entry\build\default\outputs\default\entry-default-unsigned.hap'
  if (-not (Test-Path -LiteralPath $hap)) { throw 'Hvigor returned success but the expected unsigned HAP was not created.' }
  $file = Get-Item -LiteralPath $hap
  $hash = (Get-FileHash -LiteralPath $hap -Algorithm SHA256).Hash.ToLowerInvariant()
  "SOURCE_SHA=$actualSha"
  "TEMPORARY_COMPILE_SDK=26.0.1 (compatibleSdkVersion and targetSdkVersion unchanged)"
  "HAP_PATH=$hap"
  "HAP_BYTES=$($file.Length)"
  "HAP_SHA256=$hash"
  'SIGNING=unsigned; deployment/device execution was not attempted'
}
finally {
  if ($created) {
    & git -C $repoRoot worktree remove --force $worktree
    if ($LASTEXITCODE -ne 0) { Write-Warning "Could not remove temporary worktree: $worktree" }
  }
}
