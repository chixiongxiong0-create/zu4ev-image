param([switch]$Full)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
$out="$repo/build/ffc/sim"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
 $bin='D:/Xilinx/2025.1/Vivado/bin'
 & "$bin/xvlog.bat" --sv "$repo/platform/zu4ev/isp/ffc/ffc_dual_ram.sv" "$repo/platform/zu4ev/isp/ffc/ffc_stats.sv" "$repo/platform/zu4ev/isp/ffc/ffc_raw10.sv" "$PSScriptRoot/tb_ffc.sv"
 if($LASTEXITCODE){throw 'compile'}
 $opts=@();if($Full){$opts=@('-generic_top','"W=1280"','-generic_top','"H=1024"')}
 & "$bin/xelab.bat" tb_ffc @opts -s ffc_tb
 if($LASTEXITCODE){throw 'elaboration'}
 & "$bin/xsim.bat" ffc_tb -runall 2>&1 | Tee-Object -FilePath result.log
 if($LASTEXITCODE -or !(Select-String -Path result.log -Pattern 'FFC_PASS') -or (Select-String -Path result.log -Pattern 'Fatal:|ERROR:')){throw 'simulation'}
} finally {Pop-Location}
