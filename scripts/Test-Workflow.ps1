# Runs .github/workflows/build.yml locally, as faithfully as a Windows job can be reproduced.
#
# `act` is the usual answer and it does not apply: it runs the job in a Linux container, and this one
# is windows-latest because webview is compiled with MSVC and build.ps1 rewrites a PE header. What is
# reproducible is the part that actually breaks, which is the checkout.
#
# The runner starts from a clean clone. Everything here therefore starts from `git ls-files`, copied
# into a scratch directory: exactly the files a checkout would receive, and nothing else. That is what
# catches the one failure a local build can never see, which is a file the build needs and nobody
# committed.
#
#   .\scripts\Test-Workflow.ps1           # reuse the dependency cache, like a warm CI run
#   .\scripts\Test-Workflow.ps1 -Fresh    # fetch and compile every dependency again
#   .\scripts\Test-Workflow.ps1 -Keep     # leave the scratch tree behind to poke at
#
# Exits non-zero on the first failing step, the same way the job would.

param(
    [switch]$Fresh,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

$scratch = Join-Path $env:TEMP 'wxl-hub-workflow'
$cache   = Join-Path $env:TEMP 'wxl-hub-workflow-cache'   # stands in for actions/cache

$step = 0
function Step($name) {
    $script:step++
    Write-Host ''
    Write-Host ("=== {0}. {1} " -f $script:step, $name).PadRight(78, '=') -ForegroundColor Cyan
}
function Ok($text)   { Write-Host "  ok    $text" -ForegroundColor Green }
function Note($text) { Write-Host "  ---   $text" -ForegroundColor DarkGray }
function Die($text)  { Write-Host "  FAIL  $text" -ForegroundColor Red; exit 1 }

# Runs a step and returns its exit code, and only its exit code.
#
# The child's output goes to the host rather than down the pipeline, which is not a formatting
# preference: a bare `& $exe` inside a function makes every line the program printed part of that
# function's return value, so the caller ends up with an array of output followed by the number it
# actually wanted. `if ($rc -ne 0)` then compares against the whole array and reports a failure that
# never happened, with the real output nowhere to be seen.
function Run($exe, [string[]]$arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exe @arguments | Out-Host
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
}

Write-Host ''
Write-Host '  wxl-hub: build.yml, run locally' -ForegroundColor White
Write-Host "  scratch $scratch"

# --- the workflow file has to name things that exist ------------------------

Step 'Workflow references'

$wf = Join-Path $root '.github\workflows\build.yml'
if (-not (Test-Path $wf)) { Die "no workflow at $wf" }
$text = Get-Content $wf -Raw

# Not a YAML parse: what goes wrong in practice is a step naming a script that was renamed or never
# committed, and that is answered by looking for the paths themselves.
foreach ($needed in 'scripts/Get-Deps.ps1', 'scripts\Get-Deps.ps1', 'scripts\check', 'build.ps1',
                    'build/wxl-hub.exe') {
    if ($text -match [regex]::Escape($needed)) { Note "workflow names $needed" }
}
foreach ($path in 'scripts\Get-Deps.ps1', 'scripts\check\main.lua', 'build.ps1') {
    if (-not (Test-Path (Join-Path $root $path))) { Die "workflow needs $path and it is not there" }
}
Ok 'every script the workflow calls exists'

# --- actions/checkout -------------------------------------------------------

Step 'actions/checkout (tracked files only)'

Push-Location $root
$tracked = & git ls-files
$rc = $LASTEXITCODE
Pop-Location
if ($rc -ne 0) { Die 'git ls-files failed; is this a repository yet?' }

if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
New-Item -ItemType Directory -Force $scratch | Out-Null

foreach ($rel in $tracked) {
    $src = Join-Path $root $rel
    if (-not (Test-Path $src)) { continue }        # staged deletion
    $dst = Join-Path $scratch ($rel -replace '/', '\')
    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
    Copy-Item $src $dst -Force
}
Ok ("{0} files checked out" -f $tracked.Count)

# Anything the working tree has that the checkout does not is exactly what CI would be missing.
Note 'deps\ arrives empty, as it does on a runner'

# --- actions/cache ----------------------------------------------------------

Step 'actions/cache'

if ($Fresh) {
    if (Test-Path $cache) { Remove-Item -Recurse -Force $cache }
    Note 'cache dropped, this run fetches and compiles everything'
}

if (Test-Path $cache) {
    Copy-Item (Join-Path $cache '*') (Join-Path $scratch 'deps') -Recurse -Force
    Ok 'cache hit, deps restored'
} else {
    Note 'cache miss'
}

# --- Fetch dependencies -----------------------------------------------------

Step 'Fetch dependencies'

Push-Location $scratch
$rc = Run 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\scripts\Get-Deps.ps1')
Pop-Location
if ($rc -ne 0) { Die 'Get-Deps.ps1 failed' }

New-Item -ItemType Directory -Force $cache | Out-Null
Copy-Item (Join-Path $scratch 'deps\*') $cache -Recurse -Force
Ok 'dependencies present, cache saved'

# --- Compile check ----------------------------------------------------------

Step 'Compile check'

Push-Location $scratch
$rc = Run '.\deps\luvi\luvi-Windows-amd64-luajit-regular.exe' @('scripts\check')
Pop-Location
if ($rc -ne 0) { Die 'sources do not compile' }
Ok 'sources compile'

# --- Build ------------------------------------------------------------------

Step 'Build'

Push-Location $scratch
$rc = Run 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\build.ps1', '-Compile')
Pop-Location
if ($rc -ne 0) { Die 'build.ps1 failed' }

$exe = Join-Path $scratch 'build\wxl-hub.exe'
if (-not (Test-Path $exe)) { Die 'the build produced no wxl-hub.exe' }
Ok ("wxl-hub.exe  {0:N1} MB" -f ((Get-Item $exe).Length / 1MB))

# --- Name the artifact ------------------------------------------------------
# The same expression the workflow step evaluates, checked on both sides of its branch rather than
# only on the one this run happens to be.

Step 'Name the artifact'

function Get-ArtifactVersion($ref, $sha) {
    if ($ref -like 'refs/tags/v*') { return $ref -replace '^refs/tags/v', '' }
    return 'dev-' + $sha.Substring(0, 7)
}
$cases = @(
    @{ ref = 'refs/tags/v1.0.0';  sha = 'a1b2c3d4e5f6a7b8'; want = '1.0.0' },
    @{ ref = 'refs/heads/main';   sha = 'a1b2c3d4e5f6a7b8'; want = 'dev-a1b2c3d' }
)
foreach ($c in $cases) {
    $got = Get-ArtifactVersion $c.ref $c.sha
    if ($got -ne $c.want) { Die ("{0} -> {1}, expected {2}" -f $c.ref, $got, $c.want) }
    Note ("{0,-20} -> wxl-hub-{1}" -f $c.ref, $got)
}
Ok 'artifact naming holds for a tag and for a branch'

# --- what the runner would upload -------------------------------------------

Step 'Result'

# The subsystem byte is the one thing a headless check can still say about the artifact: 2 is GUI,
# and a 3 here means the console window came back.
$fs = [System.IO.File]::OpenRead($exe)
try {
    $br = New-Object System.IO.BinaryReader($fs)
    $fs.Position = 0x3C
    $pe = $br.ReadUInt32()
    $fs.Position = $pe + 4 + 20 + 0x44
    $subsystem = $br.ReadUInt16()
} finally { $fs.Dispose() }

if ($subsystem -ne 2) { Die "subsystem is $subsystem, expected 2 (GUI)" }
Ok 'subsystem 2 (GUI, no console)'

Write-Host ''
Write-Host ("  artifact  {0}" -f $exe)
Write-Host ("  release   drafted only on a refs/tags/v* push")
Write-Host ''

if (-not $Keep) {
    Remove-Item -Recurse -Force $scratch
    Write-Host '  scratch removed (-Keep to inspect it)'
} else {
    Write-Host "  scratch kept at $scratch"
}
Write-Host ''
Write-Host '  build.yml would pass.' -ForegroundColor Green
Write-Host ''
