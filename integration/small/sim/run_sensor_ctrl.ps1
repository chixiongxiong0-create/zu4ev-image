param([string]$VivadoBin = 'D:/Xilinx/2025.1/Vivado/bin')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$build = Join-Path $repo 'build/sensor_ctrl_test'
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
  & "$VivadoBin/xvlog.bat" -sv "$repo/integration/small/rtl/ibex_sensor_i2c.sv" "$repo/integration/small/rtl/ibex_sensor_ctrl.sv" "$repo/integration/small/sim/tb_sensor_ctrl.sv"
  if ($LASTEXITCODE) { throw 'xvlog failed' }
  & "$VivadoBin/xelab.bat" --timescale 1ns/1ps tb_sensor_ctrl -s sensor_ctrl
  if ($LASTEXITCODE) { throw 'xelab failed' }
  $output = & "$VivadoBin/xsim.bat" sensor_ctrl -runall
  $output | Select-String -Pattern 'PASS |Fatal:|Error:'
  if ($LASTEXITCODE -or ($output -match 'Fatal:|Error:') -or -not ($output -match '^PASS sensor ownership idle reset drain rearm quiesce')) { throw 'simulation did not pass' }
} finally { Pop-Location }
