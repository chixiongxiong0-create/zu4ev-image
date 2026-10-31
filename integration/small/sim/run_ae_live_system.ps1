param([string]$Vivado = 'D:/Xilinx/2025.1/Vivado/bin/vivado.bat', [ValidateSet('normal','nack','no_frames')][string]$Scenario = 'normal')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$out = Join-Path $repo "build/ae_live_system_run_$Scenario"
New-Item -ItemType Directory -Force $out | Out-Null
$console = Join-Path $out 'console.log'
$env:IBEX_AE_TEST = $Scenario
& $Vivado -mode batch -notrace -source (Join-Path $PSScriptRoot 'run_ae_live_system.tcl') -log (Join-Path $out 'vivado.log') -journal (Join-Path $out 'vivado.jou') *> $console
$code = $LASTEXITCODE
$results = Select-String -Path $console -Pattern 'PASS real Ibex AE|Fatal:|ERROR:|DATA_ERROR'
$results
if ($code -ne 0 -or ($results -match 'Fatal:|ERROR:|DATA_ERROR') -or -not ($results -match 'PASS real Ibex AE')) { throw 'AE live system verification failed' }
