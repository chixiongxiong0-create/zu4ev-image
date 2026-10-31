param([string]$VivadoBin = 'D:/Xilinx/2025.1/Vivado/bin')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$build = Join-Path $repo 'build/sensor_i2c_test'
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
  & "$VivadoBin/xvlog.bat" -sv "$repo/integration/small/rtl/ibex_sensor_i2c.sv" "$repo/integration/small/sim/tb_sensor_i2c.sv"
  if ($LASTEXITCODE) { throw 'xvlog failed' }
  & "$VivadoBin/xelab.bat" --timescale 1ns/1ps tb_sensor_i2c -s sensor_i2c
  if ($LASTEXITCODE) { throw 'xelab failed' }
  $output = & "$VivadoBin/xsim.bat" sensor_i2c -runall
  $output | Select-String -Pattern 'PASS |Fatal:|Error:'
  if ($LASTEXITCODE -or ($output -match 'Fatal:|Error:') -or -not ($output -match '^PASS sensor I2C write repeated-start read NACK timeout bus release')) { throw 'simulation did not pass' }
} finally { Pop-Location }
