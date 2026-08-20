[CmdletBinding()]
param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2024.1\bin"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado simulator tool not found: $tool"
    }
}

$tests = @(
    [pscustomobject]@{
        FileList = "rtl/filelists/current/tile_window_tb.f"
        Top = "tb_tile_window_path"
    },
    [pscustomobject]@{
        FileList = "rtl/filelists/current/tile_conv_tb.f"
        Top = "tb_single_conv_tile"
    },
    [pscustomobject]@{
        FileList = "rtl/filelists/current/tile_conv_axi_tb.f"
        Top = "tb_single_conv_tile_axi"
    },
    [pscustomobject]@{
        FileList = "rtl/filelists/current/tile_conv_multi_ic_axi_tb.f"
        Top = "tb_multi_ic_conv_tile_axi"
    }
)

Push-Location $repoRoot
try {
    foreach ($test in $tests) {
        $snapshot = "$($test.Top)_sim"
        Write-Host "CNN_TEST: compile $($test.Top)"

        & $xvlog -f $test.FileList
        if ($LASTEXITCODE -ne 0) {
            throw "xvlog failed for $($test.Top) with exit code $LASTEXITCODE"
        }

        & $xelab $test.Top -s $snapshot
        if ($LASTEXITCODE -ne 0) {
            throw "xelab failed for $($test.Top) with exit code $LASTEXITCODE"
        }

        & $xsim $snapshot -runall
        if ($LASTEXITCODE -ne 0) {
            throw "xsim failed for $($test.Top) with exit code $LASTEXITCODE"
        }
    }
}
finally {
    Pop-Location
}

Write-Host "CNN_TEST: PASS all 4 RTL tests"
