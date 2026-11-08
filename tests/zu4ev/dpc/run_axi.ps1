$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../../..").Path
$isp = "$repo/platform/zu4ev/isp"
$out = "$repo/build/dpc/sim-axi"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
    $bin = 'D:/Xilinx/2025.1/Vivado/bin'
    & "$bin/xvlog.bat" --sv "$isp/ffc/ffc_dual_ram.sv" "$isp/ffc/ffc_stats.sv" "$isp/ffc/ffc_raw10.sv" `
        "$isp/dpc/dpc_probe.sv" "$isp/dpc/dpc_raw10.sv" "$isp/ltm/isp_axi_regs.sv" `
        "$isp/ae/ae_stats_raw10.sv" "$isp/isp_capture_frontend.sv" `
        "$PSScriptRoot/ltm_ingress_stub.sv" "$PSScriptRoot/tb_dpc_axi.sv"
    if ($LASTEXITCODE) { throw 'AXI compile failed' }
    & "$bin/xelab.bat" tb_dpc_axi -s tb_dpc_axi_snapshot
    if ($LASTEXITCODE) { throw 'AXI elaboration failed' }
    & "$bin/xsim.bat" tb_dpc_axi_snapshot -runall 2>&1 | Tee-Object 'result.log'
    if ($LASTEXITCODE -or !(Select-String result.log -Pattern DPC_AXI_PASS) -or
        (Select-String result.log -Pattern 'Fatal:|ERROR:')) { throw 'AXI simulation failed' }
} finally { Pop-Location }
