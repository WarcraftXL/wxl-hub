# Builds wxl-hub.exe: a luvi binary with the application zipped onto the end.
#
# Only what the app needs is staged. Bundling the repo as-is would pull in deps\luvi (5.6 MB of
# runtime we are already using as the container) and the .lib files, which nothing loads.
#
#   .\build.ps1              -> build\wxl-hub.exe
#   .\build.ps1 -Compile     -> bytecode-compiled, smaller and faster to start
#   .\build.ps1 -Run         -> build, then launch it
#
# -Release is what the build calls itself. The launcher compares that against the newest published
# release to decide whether to install it, so a build left at the default advertises itself as dev.

param(
    [switch]$Compile,
    [switch]$Run,

    # The version this build calls itself. CI passes the tag; a developer has no reason to.
    [string]$Release = 'dev'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

. (Join-Path $root 'scripts\Native.ps1')

$luvi = Join-Path $root 'deps\luvi\luvi-Windows-amd64-luajit-regular.exe'
if (-not (Test-Path $luvi)) { throw "missing luvi: $luvi" }

Add-Type -Namespace Win32 -Name Res -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName,
                                         ushort wLanguage, byte[] lpData, uint cbData);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);
'@

# Writes RT_ICON + RT_GROUP_ICON into a PE.
#
# This must run on a plain luvi binary, never on the finished bundle: UpdateResource rewrites the
# section table and moves the end of the file, and luvi's zip is appended there and located from the
# end. Patching after the append would leave an executable whose bundle can no longer be found.
function Set-ExeIcon($exe, $icoPath) {
    $ico = [System.IO.File]::ReadAllBytes($icoPath)
    $count = [BitConverter]::ToUInt16($ico, 4)

    $h = [Win32.Res]::BeginUpdateResource($exe, $false)
    if ($h -eq [IntPtr]::Zero) { throw "BeginUpdateResource failed on $exe" }

    $grp = New-Object System.IO.MemoryStream
    $gw  = New-Object System.IO.BinaryWriter($grp)
    $gw.Write([UInt16]0); $gw.Write([UInt16]1); $gw.Write([UInt16]$count)

    for ($i = 0; $i -lt $count; $i++) {
        $e   = 6 + 16 * $i
        $len = [BitConverter]::ToUInt32($ico, $e + 8)
        $off = [BitConverter]::ToUInt32($ico, $e + 12)
        $img = New-Object byte[] $len
        [Array]::Copy($ico, $off, $img, 0, $len)

        if (-not [Win32.Res]::UpdateResource($h, [IntPtr]3, [IntPtr]($i + 1), 0, $img, $len)) {
            throw "UpdateResource RT_ICON $($i + 1) failed"
        }
        # GRPICONDIRENTRY is the directory entry minus its 4-byte offset, plus a 2-byte resource id.
        $gw.Write($ico[$e]); $gw.Write($ico[$e + 1]); $gw.Write($ico[$e + 2]); $gw.Write($ico[$e + 3])
        $gw.Write([BitConverter]::ToUInt16($ico, $e + 4))
        $gw.Write([BitConverter]::ToUInt16($ico, $e + 6))
        $gw.Write([UInt32]$len)
        $gw.Write([UInt16]($i + 1))
    }
    $gw.Flush()
    $grpBytes = $grp.ToArray()
    if (-not [Win32.Res]::UpdateResource($h, [IntPtr]14, [IntPtr]1, 0, $grpBytes, $grpBytes.Length)) {
        throw "UpdateResource RT_GROUP_ICON failed"
    }
    $gw.Dispose()
    if (-not [Win32.Res]::EndUpdateResource($h, $false)) { throw "EndUpdateResource failed" }
}

# Flips the PE subsystem to WINDOWS_GUI so no console appears.
#
# A two-byte in-place write, which is why it is safe to do after the zip has been appended: nothing
# moves and no offset changes.
function Set-ExeGuiSubsystem($exe) {
    $fs = [System.IO.File]::Open($exe, 'Open', 'ReadWrite')
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $peOffset = $br.ReadUInt32()
        $fs.Position = $peOffset
        if ($br.ReadUInt32() -ne 0x00004550) { throw "not a PE file: $exe" }

        # Subsystem sits at OptionalHeader + 0x44 in PE32+ (COFF header is 20 bytes after the sig).
        $subsystemAt = $peOffset + 4 + 20 + 0x44
        $fs.Position = $subsystemAt
        $before = $br.ReadUInt16()
        $fs.Position = $subsystemAt
        $bw = New-Object System.IO.BinaryWriter($fs)
        $bw.Write([UInt16]2)
        $bw.Flush()
        return $before
    } finally { $fs.Dispose() }
}

$stage = Join-Path $root 'build\stage'
$out   = Join-Path $root 'build\wxl-hub.exe'

if (Test-Path (Join-Path $root 'build')) { Remove-Item -Recurse -Force (Join-Path $root 'build') }
New-Item -ItemType Directory -Force $stage | Out-Null

# A build stamp doubles as the unpack directory name, so two builds never share a cache. It is not
# the release version and cannot be: two builds of 0.1.0 have to stay apart on disk.
$version = Get-Date -Format 'yyyyMMdd-HHmmss'
Set-Content -Path (Join-Path $stage 'VERSION') -Value $version -Encoding ascii -NoNewline

# The other half of the identity: the release this build calls itself, as opposed to the folder it
# unpacks into. This is what a person reads and what the launcher compares.
Set-Content -Path (Join-Path $stage 'RELEASE') -Value $Release -Encoding ascii -NoNewline

function Stage($relative) {
    $src = Join-Path $root $relative
    $dst = Join-Path $stage $relative
    if (-not (Test-Path $src)) { throw "missing: $relative" }
    New-Item -ItemType Directory -Force (Split-Path -Parent $dst) | Out-Null
    Copy-Item $src $dst -Recurse -Force
}

Stage 'main.lua'
Stage 'core'
Stage 'ffi'
Stage 'utils'
Stage 'modules'
Stage 'views'
Stage 'assets'
Stage 'deps\lua'
Stage 'deps\htmx\htmx.min.js'

# Native libraries ride inside the zip and are written out on first launch; LoadLibrary cannot read
# them from an archive.
Stage 'deps\webview\webview.dll'
Stage 'deps\webview\WebView2Loader.dll'
Stage 'deps\sqlite\sqlite3.dll'

# Development leftovers must never ship.
Get-ChildItem $stage -Recurse -Include *.db, *.db-wal, *.db-shm | Remove-Item -Force

# luvi copies the binary it is *running as* to make the output, so the icon has to be on that copy.
$branded = Join-Path $root 'build\luvi-branded.exe'
Copy-Item $luvi $branded -Force
Set-ExeIcon $branded (Join-Path $root 'assets\logo.ico')

$luviArgs = @($stage, '--output', $out)
if ($Compile) { $luviArgs += '--compile' }

# Quiet: luvi lists every file it zips, which is a hundred lines nobody reads unless it fails.
Invoke-Native -What 'luvi' -Exe $branded -Arguments $luviArgs -Quiet
Remove-Item $branded -Force

$was = Set-ExeGuiSubsystem $out

$size = (Get-Item $out).Length
Write-Output ''
Write-Output ("  {0}" -f $out)
Write-Output ("  {0:N1} MB   build {1}   release {2}" -f ($size / 1MB), $version, $Release)
Write-Output ("  icon embedded, subsystem {0} -> 2 (GUI, no console)" -f $was)
Write-Output ''
Write-Output '  One file, two roles, told apart by where it runs from. Kept where the user put it,'
Write-Output '  it is the launcher; written by that launcher to'
Write-Output '  %LOCALAPPDATA%\WarcraftXL\hub\bin\hub.exe, it is the hub.'
Write-Output ''
Write-Output ("  Either way it unpacks to %LOCALAPPDATA%\WarcraftXL\hub\{0}\ and runs from" -f $version)
Write-Output '  there. With no console attached, both write to hub.log one level above that.'

if ($Run) { & $out }

exit 0
