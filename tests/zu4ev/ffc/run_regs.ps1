$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
$out="$repo/build/ffc/regs_sim";New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
 $bin='D:/Xilinx/2025.1/Vivado/bin'
 & "$bin/xvlog.bat" --sv "$repo/platform/zu4ev/isp/ffc/ffc_dual_ram.sv" "$repo/platform/zu4ev/isp/ffc/ffc_stats.sv" "$repo/platform/zu4ev/isp/ffc/ffc_raw10.sv" "$repo/platform/zu4ev/isp/ltm/isp_axi_regs.sv" "$PSScriptRoot/tb_ffc_regs.sv"
 if($LASTEXITCODE){throw 'compile'}
 & "$bin/xelab.bat" tb_ffc_regs -s regs_tb
 if($LASTEXITCODE){throw 'elaboration'}
 & "$bin/xsim.bat" regs_tb -runall 2>&1 | Tee-Object -FilePath result.log
 if($LASTEXITCODE -or !(Select-String result.log -Pattern FFC_AXI_PASS) -or (Select-String result.log -Pattern 'Fatal:|ERROR:')){throw 'simulation'}
}finally{Pop-Location}
