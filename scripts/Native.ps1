# Invoke-Native: run an external program and judge it by its exit code.
#
# Dot-sourced by build.ps1 and scripts\Get-Deps.ps1, for one Windows PowerShell behaviour that
# $ErrorActionPreference does not reliably suppress.
#
# A program writing to stderr is not a program that failed. git announces "Cloning into..." there,
# it warns about an annotated tag, it prints the whole detached-HEAD lecture there; CMake puts its
# warnings there; MSBuild does too. When PowerShell's own output is being captured, which is always
# under a CI runner, it wraps each of those lines in an ErrorRecord and can end a script that did
# nothing wrong. Setting the preference to Continue around the call does not reliably prevent it,
# because the wrapping happens in the pipeline processor rather than at the call.
#
# So under 5.1 the child's handles are redirected at the process level instead, straight to files.
# PowerShell never sees the stream, so it has nothing to reinterpret, and the exit code is left to
# say what happened. The cost is that output arrives when the step ends rather than while it runs,
# which is why this path is taken only where it is needed.

$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param(
        [Parameter(Mandatory)] [string]   $What,
        [Parameter(Mandatory)] [string]   $Exe,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [switch] $Quiet          # show output only if the program fails
    )

    # pwsh does not reinterpret a native program's stderr, so on it the plain call is both correct
    # and better: output streams as it happens. That matters more than it sounds. Buffering a
    # multi-minute compile means a CI log that sits on one line with no sign of life, which is
    # indistinguishable from a hang, and the buffering itself can cause one: MSBuild leaves worker
    # processes running after it exits, they inherit the redirected handles, and waiting on those
    # never finishes.
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        & $Exe @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$What failed (exit $LASTEXITCODE)" }
        return
    }

    # Start-Process joins the array with spaces, so anything holding one has to carry its own quotes.
    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '\s' -and $_ -notmatch '^".*"$') { '"' + $_ + '"' } else { $_ }
    }

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $Exe -ArgumentList $quoted `
                              -NoNewWindow -Wait -PassThru `
                              -RedirectStandardOutput $outFile -RedirectStandardError $errFile

        $failed = $proc.ExitCode -ne 0
        if ($failed -or -not $Quiet) {
            foreach ($file in $outFile, $errFile) {
                Get-Content $file -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.Trim()) { Write-Host "      $_" }
                }
            }
        }
        if ($failed) { throw "$What failed (exit $($proc.ExitCode))" }
    }
    finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}
