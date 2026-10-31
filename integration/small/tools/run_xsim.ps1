param([string]$Vivado = 'D:\Xilinx\2025.1\Vivado\bin\vivado.bat')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$build = Join-Path $repo 'build/ibex_small'
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
    & $Vivado -mode batch -notrace -source (Join-Path $PSScriptRoot 'run_xsim.tcl') -log run_xsim.log -journal run_xsim.jou
    if ($LASTEXITCODE -ne 0) { throw "Vivado failed: $LASTEXITCODE" }
    $log = Join-Path $build 'xsim/ibex_small.sim/sim_1/behav/xsim/simulate.log'
    $text = Get-Content -LiteralPath $log -Raw
    if ($text -match 'Fatal:|Error:' -or $text -notmatch 'IBEX_SMALL_PASS' -or $text -notmatch 'IBEX_MEMORY_PASS' -or $text -notmatch 'IBEX_AXI_PASS') {
        throw "XSim self-test failed; inspect $log"
    }
    $text
} finally { Pop-Location }
