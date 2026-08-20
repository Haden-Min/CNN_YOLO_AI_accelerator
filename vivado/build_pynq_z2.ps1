[CmdletBinding()]
param(
    [string]$VivadoBat = "C:\Xilinx\Vivado\2024.1\bin\vivado.bat"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
    throw "Vivado 2024.1 launcher not found: $VivadoBat"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$buildTcl = (Resolve-Path (Join-Path $PSScriptRoot "build_bitstream.tcl")).Path
$buildTclForVivado = $buildTcl.Replace("\", "/")

Push-Location $repoRoot
try {
    Write-Host "CNN_BUILD: repository=$repoRoot"
    & $VivadoBat -mode batch -notrace -source $buildTclForVivado
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$artifacts = Join-Path $repoRoot "build\vivado\artifacts"
$requiredFiles = @(
    (Join-Path $artifacts "pynq_z2_cnn.bit"),
    (Join-Path $artifacts "pynq_z2_cnn.hwh"),
    (Join-Path $artifacts "timing_summary.rpt"),
    (Join-Path $artifacts "utilization.rpt"),
    (Join-Path $artifacts "drc.rpt")
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required build artifact is missing: $file"
    }
}

Write-Host "CNN_BUILD: PASS artifacts=$artifacts"
