param([string]$VivadoBin = 'D:/Xilinx/2025.1/Vivado/bin')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$out = Join-Path $repo 'build/nv12_validation'
New-Item -ItemType Directory -Force $out | Out-Null
$rtl = Join-Path $repo 'platform/zu4ev/isp/nv12'
$tests = @('tb','tb_full','tb_ddr','tb_ddr_full','tb_pool','tb_sink','tb_capture','tb_regs','tb_peripheral','tb_stop')
Push-Location $out
try {
    $product = @('isp_yuy2_nv12','nv12_plane_fifo','nv12_ddr_writer','nv12_buffer_pool','nv12_isp_ddr_sink','nv12_capture_output','nv12_axi_regs','nv12_capture_peripheral') | ForEach-Object { Join-Path $rtl "$_.v" }
    & "$VivadoBin/xvlog.bat" @product
    if ($LASTEXITCODE -ne 0) { throw 'RTL compile failed' }
    $benches = $tests | ForEach-Object { Join-Path $PSScriptRoot "$_.sv" }
    & "$VivadoBin/xvlog.bat" --sv @benches
    if ($LASTEXITCODE -ne 0) { throw 'Test compile failed' }
    foreach ($test in $tests) {
        & "$VivadoBin/xelab.bat" $test -s "${test}_snapshot"
        if ($LASTEXITCODE -ne 0) { throw "Elaboration failed: $test" }
        $output = & "$VivadoBin/xsim.bat" "${test}_snapshot" -runall 2>&1
        $status = $LASTEXITCODE
        $output | Set-Content "$test.result.txt"
        $text = $output -join "`n"
        if ($status -ne 0 -or $text -match 'Fatal:|FATAL|ERROR:' -or $text -notmatch 'PASS') { throw "Simulation failed: $test" }
        $output | Select-String 'PASS'
    }
} finally { Pop-Location }
