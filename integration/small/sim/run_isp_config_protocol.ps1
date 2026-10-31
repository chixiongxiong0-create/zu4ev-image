param(
  [string]$VivadoBin = 'D:/Xilinx/2025.1/Vivado/bin',
  [string]$Platform = 'E:/workspace/AI_Projects/ZU4EV/zynq-zu4ev_platform'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$build = Join-Path $repo 'build/isp_protocol_test'
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
  & "$VivadoBin/xvlog.bat" -sv "$repo/integration/small/rtl/ibex_isp_cfg_cdc.sv" "$repo/integration/small/rtl/ibex_native_to_axi_lite.sv" "$repo/integration/small/rtl/ibex_isp_cfg_owner.sv" "$Platform/isp/ltm/isp_axi_regs.sv" "$repo/integration/small/sim/tb_isp_config_protocol.sv"
  if ($LASTEXITCODE) { throw 'xvlog failed' }
  & "$VivadoBin/xelab.bat" --timescale 1ns/1ps tb_isp_config_protocol -s isp_protocol
  if ($LASTEXITCODE) { throw 'xelab failed' }
  $output = & "$VivadoBin/xsim.bat" isp_protocol -runall
  $output
  if ($LASTEXITCODE -or -not ($output -match '^PASS ownership deny grant revoke native AXI errors masks')) { throw 'simulation did not pass' }
} finally { Pop-Location }
