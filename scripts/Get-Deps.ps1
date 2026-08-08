# Fetches the vendored binaries into deps\.
#
# These are not committed: they are someone else's release artifacts, they are 8.8 MB of them, and
# pinning them here means a checkout and a CI runner get the same bytes rather than whatever happened
# to be on a developer's disk. Every version is pinned; nothing resolves to "latest".
#
#   .\scripts\Get-Deps.ps1           # fetch what is missing
#   .\scripts\Get-Deps.ps1 -Force    # fetch everything again
#
# Three of the four are published binaries and are simply downloaded. webview has tags but no
# released DLL, so it is built from source, which needs git, CMake and the MSVC C++ toolchain.

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest crawl

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$deps = Join-Path $root 'deps'

# --- pinned versions -------------------------------------------------------

$LUVI_VERSION    = 'v2.15.0'
$LUVI_ASSET      = 'luvi-Windows-amd64-luajit-regular.exe'
$SQLITE_VERSION  = '3.53.4'
$WEBVIEW2_NUGET  = '1.0.1150.38'
$WEBVIEW_TAG     = '0.12.0'

# ---------------------------------------------------------------------------

. (Join-Path $PSScriptRoot 'Native.ps1')

function Step($text) { Write-Host "  $text" }

function Need($path) {
    if ($Force) { return $true }
    if (Test-Path $path) { Step "have  $(Resolve-Path -Relative $path)"; return $false }
    return $true
}

function Save-Url($url, $dest) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 300
    Step ("got   {0}  ({1:N0} bytes)" -f (Split-Path -Leaf $dest), (Get-Item $dest).Length)
}

# Pulls one file out of a zip without unpacking the rest of it.
function Copy-FromZip($zip, $entrySuffix, $dest) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entry = $archive.Entries | Where-Object { $_.FullName -like "*$entrySuffix" } | Select-Object -First 1
        if (-not $entry) { throw "no entry matching *$entrySuffix in $zip" }
        New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
    } finally { $archive.Dispose() }
    Step ("took  {0}  ({1:N0} bytes)" -f (Split-Path -Leaf $dest), (Get-Item $dest).Length)
}

# --- luvi ------------------------------------------------------------------
# The runtime, and also the container: build.ps1 appends the application to a copy of this file.

$luvi = Join-Path $deps "luvi\$LUVI_ASSET"
if (Need $luvi) {
    Step "luvi $LUVI_VERSION"
    Save-Url "https://github.com/luvit/luvi/releases/download/$LUVI_VERSION/$LUVI_ASSET" $luvi
}

# --- sqlite ----------------------------------------------------------------
# The download path carries a year folder that changes between releases, so it is read out of the
# machine-readable product list rather than guessed. The version itself stays pinned.

$sqlite = Join-Path $deps 'sqlite\sqlite3.dll'
if (Need $sqlite) {
    Step "sqlite $SQLITE_VERSION"
    $page = (Invoke-WebRequest 'https://sqlite.org/download.html' -UseBasicParsing -TimeoutSec 120).Content
    $line = $page -split "`n" | Where-Object { $_ -match "^PRODUCT,$([regex]::Escape($SQLITE_VERSION)),(\S*sqlite-dll-win-x64\S*\.zip)," }
    if (-not $line) { throw "sqlite.org no longer lists a win-x64 DLL for $SQLITE_VERSION" }
    $relative = $Matches[1]

    $zip = Join-Path $env:TEMP 'wxl-sqlite.zip'
    Save-Url "https://sqlite.org/$relative" $zip
    Copy-FromZip $zip 'sqlite3.dll' $sqlite
    Remove-Item $zip -Force
}

# --- WebView2Loader --------------------------------------------------------
# Microsoft ships this inside the SDK's NuGet package and nowhere else.

$loader = Join-Path $deps 'webview\WebView2Loader.dll'
if (Need $loader) {
    Step "WebView2 SDK $WEBVIEW2_NUGET"
    $pkg = Join-Path $env:TEMP 'wxl-webview2.nupkg'
    Save-Url ("https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/{0}/microsoft.web.webview2.{0}.nupkg" -f $WEBVIEW2_NUGET) $pkg
    Copy-FromZip $pkg 'build/native/x64/WebView2Loader.dll' $loader
    Remove-Item $pkg -Force
}

# --- webview ---------------------------------------------------------------
# Tagged but never released as a binary, so this one is compiled. ffi/webview.lua binds the API that
# returns webview_error_t, which is 0.11 and later; it checks webview_version() at startup and
# refuses a mismatch rather than misbehaving, so a wrong tag here fails loudly.

$webview = Join-Path $deps 'webview\webview.dll'
if (Need $webview) {
    Step "webview $WEBVIEW_TAG (from source)"
    foreach ($tool in 'git', 'cmake') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "$tool is needed to build webview, along with the MSVC C++ toolchain."
        }
    }

    # TEMP, and short. MSBuild warns that an output directory under the temporary directory spoils
    # incremental builds, which is true and irrelevant: this tree is built once and deleted. Putting
    # it inside the repository instead silences that warning and buys a worse problem, because
    # MSBuild's file tracker still writes paths like
    # build\CMakeFiles\CMakeScratch\TryCompile-xxxxxx\cmTC_xxxxx.dir\Debug\cmTC_xxxxx.tlog\... and a
    # checkout a few folders deep pushes those past MAX_PATH. It fails as FTK1011, which reads as a
    # broken compiler rather than as a long name.
    $work = Join-Path $env:TEMP 'wxl-webview-build'
    if (Test-Path $work) { Remove-Item -Recurse -Force $work }

    # -Quiet only has an effect under Windows PowerShell, where output has to be buffered; on pwsh
    # these stream. Both are loud and none of it matters unless one fails: the tag is annotated so
    # git warns about it, and CMake reports the linters it did not find.
    Step '  cloning'
    Invoke-Native -What 'git clone' -Exe 'git' -Quiet -Arguments @(
        'clone', '--quiet', '--depth', '1', '--branch', $WEBVIEW_TAG,
        'https://github.com/webview/webview.git', $work)

    # Everything that is not the DLL is turned off, and the checks are the reason this list is long
    # rather than lazy.
    #
    # webview's own clang-format and clang-tidy targets run over webview's own source, and it makes
    # them fatal when it detects CI (WEBVIEW_STRICT_CHECKS defaults to WEBVIEW_IS_CI). A runner has
    # clang-format installed and a developer's machine usually does not, so the same tag builds
    # locally and fails in CI, on a formatting opinion about a header we only ever consume. Building
    # a dependency is not the moment to enforce its authors' style.
    #
    # The static library is off for a duller reason: it is the same translation unit compiled a
    # second time, and nothing here links it.
    Step '  configuring (this fetches the WebView2 headers)'
    Invoke-Native -What 'cmake configure' -Exe 'cmake' -Quiet -Arguments @(
        '-S', $work, '-B', "$work\build", '-A', 'x64',
        '-DCMAKE_BUILD_TYPE=Release',
        '-DWEBVIEW_ENABLE_CHECKS=OFF',
        '-DWEBVIEW_ENABLE_CLANG_FORMAT=OFF',
        '-DWEBVIEW_ENABLE_CLANG_TIDY=OFF',
        '-DWEBVIEW_BUILD_SHARED_LIBRARY=ON',
        '-DWEBVIEW_BUILD_STATIC_LIBRARY=OFF',
        '-DWEBVIEW_ENABLE_PACKAGING=OFF',
        '-DWEBVIEW_INSTALL_TARGETS=OFF',
        '-DWEBVIEW_BUILD_TESTS=OFF', '-DWEBVIEW_BUILD_EXAMPLES=OFF', '-DWEBVIEW_BUILD_DOCS=OFF')

    # -nodeReuse:false is not a tuning knob. MSBuild keeps its worker processes alive for minutes
    # after a build by default, and they hold on to whatever handles they inherited; a parent that
    # waits on those waits forever. Compiling one translation unit gains nothing from reuse anyway.
    Step '  compiling (a couple of minutes, cold)'
    Invoke-Native -What 'cmake build' -Exe 'cmake' -Quiet -Arguments @(
        '--build', "$work\build", '--config', 'Release', '--', '-nodeReuse:false')

    # Located rather than hardcoded: which subdirectory the DLL lands in has moved between releases.
    $built = Get-ChildItem "$work\build" -Recurse -Filter 'webview.dll' | Select-Object -First 1
    if (-not $built) { throw "the build produced no webview.dll" }

    New-Item -ItemType Directory -Force (Split-Path -Parent $webview) | Out-Null
    Copy-Item $built.FullName $webview -Force
    Step ("built {0}  ({1:N0} bytes)" -f 'webview.dll', (Get-Item $webview).Length)
    Remove-Item -Recurse -Force $work
}

Write-Host ''
Write-Host '  deps ready:'
foreach ($f in $luvi, $sqlite, $loader, $webview) {
    Write-Host ("    {0,-46} {1,10:N0} bytes" -f (Resolve-Path -Relative $f), (Get-Item $f).Length)
}
Write-Host ''

# The exit code is stated rather than inferred. Under Windows PowerShell a script whose native
# children wrote anything to stderr can exit 1 with every step having succeeded, and git says
# "Cloning into..." there as a matter of course.
exit 0
