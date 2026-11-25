param([switch]$Full)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../../..").Path
$variant = if ($Full) { 'full' } else { 'small' }
$out = "$repo/build/dpc/sim-$variant"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
    $bin = 'D:/Xilinx/2025.1/Vivado/bin'
    & "$bin/xvlog.bat" --sv "$repo/platform/zu4ev/isp/ffc/ffc_dual_ram.sv" `
        "$repo/platform/zu4ev/isp/dpc/dpc_probe.sv" "$repo/platform/zu4ev/isp/dpc/dpc_raw10.sv" `
        "$PSScriptRoot/tb_dpc.sv" "$PSScriptRoot/tb_probe.sv"
    if ($LASTEXITCODE) { throw 'DPC compile failed' }
    $opts = @()
    if ($Full) { $opts = @('-generic_top','"W=1280"','-generic_top','"H=1024"') }
    foreach ($bench in @('tb_dpc','tb_probe')) {
        $generics = if ($bench -eq 'tb_dpc') { $opts } else { @() }
        & "$bin/xelab.bat" $bench @generics -s "${bench}_snapshot"
        if ($LASTEXITCODE) { throw "$bench elaboration failed" }
        & "$bin/xsim.bat" "${bench}_snapshot" -runall 2>&1 | Tee-Object "$bench.result.log"
        if ($LASTEXITCODE -or !(Select-String "$bench.result.log" -Pattern 'DPC_.*PASS') -or
            (Select-String "$bench.result.log" -Pattern 'Fatal:|ERROR:')) { throw "$bench failed" }
    }
} finally { Pop-Location }
