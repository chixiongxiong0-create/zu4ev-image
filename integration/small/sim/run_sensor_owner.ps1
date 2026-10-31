param([string]$VivadoBin = 'D:/Xilinx/2025.1/Vivado/bin', [string]$Platform = 'E:/workspace/AI_Projects/ZU4EV/zynq-zu4ev_platform')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$build = Join-Path $repo 'build/sensor_owner_test'
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
  & "$VivadoBin/xvlog.bat" -sv "$repo/integration/small/rtl/ibex_isp_cfg_cdc.sv" "$repo/integration/small/rtl/ibex_native_to_axi_lite.sv" "$repo/integration/small/rtl/ibex_isp_cfg_owner.sv" "$Platform/isp/ltm/isp_axi_regs.sv" "$repo/integration/small/sim/tb_sensor_owner.sv"
  if ($LASTEXITCODE) { throw 'xvlog failed' }
  & "$VivadoBin/xelab.bat" --timescale 1ns/1ps tb_sensor_owner -s sensor_owner
  if ($LASTEXITCODE) { throw 'xelab failed' }
  $output = & "$VivadoBin/xsim.bat" sensor_owner -runall
  $output | Select-String -Pattern 'PASS |Fatal:|Error:'
  if ($LASTEXITCODE -or ($output -match 'Fatal:|Error:') -or -not ($output -match '^PASS sensor owner ABI run quiesce readback')) { throw 'simulation did not pass' }
} finally { Pop-Location }
