# Rebuilds scripts/RotHelper.dll from src/RotHelper.cs.
# Run from any working directory; paths are resolved relative to this script.

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot
$srcFile = Join-Path $PSScriptRoot 'RotHelper.cs'
$outDir  = Join-Path $root 'scripts'
$outDll  = Join-Path $outDir 'RotHelper.dll'

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$src = Get-Content -LiteralPath $srcFile -Raw
$sw  = [Diagnostics.Stopwatch]::StartNew()
Add-Type -TypeDefinition $src -Language CSharp -OutputAssembly $outDll
$sw.Stop()

$size = (Get-Item $outDll).Length
"Built $outDll  ($size bytes, $([int]$sw.ElapsedMilliseconds) ms)"
