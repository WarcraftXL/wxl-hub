# Runs the hub from source, with templates re-read on every request.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

& (Join-Path $root 'deps\luvi\luvi-Windows-amd64-luajit-regular.exe') .
