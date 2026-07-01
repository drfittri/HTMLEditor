$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

Write-Host "=== HTML Agent Editor Windows Build ==="
Write-Host "Project: $ProjectDir"
Write-Host ""

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm is required. Install Node.js LTS, then run this script again."
}

npm install
npm run check
npm run build:win

Write-Host ""
Write-Host "Build complete. Installer output is in:"
Write-Host "$ProjectDir\dist"
