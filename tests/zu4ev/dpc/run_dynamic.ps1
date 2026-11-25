param([switch]$Full)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../../..").Path
$isp = "$repo/platform/zu4ev/isp"
$out = "$repo/build/dpc/sim-dynamic-run"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
    $bin = 'D:/Xilinx/2025.1/Vivado/bin'
    & "$bin/xvlog.bat" --sv "$isp/dpc/dpc_dynamic_window.sv" "$isp/dpc/dpc_dynamic_kernel.sv" `
        "$isp/dpc/dpc_dynamic_raw10.sv" "$PSScriptRoot/tb_dpc_dynamic.sv" `
        "$PSScriptRoot/tb_dpc_window.sv" "$PSScriptRoot/tb_dpc_window_blocked.sv"
    if ($LASTEXITCODE) { throw 'dynamic DPC compile failed' }

    $runs = @(@{Name='tb_dpc_window'; Snapshot='tb_dpc_window'; Pattern='DPC_WINDOW_PASS'; Generics=@()},
              @{Name='tb_dpc_window'; Snapshot='tb_dpc_window_min'; Pattern='DPC_WINDOW_PASS';
                Generics=@('-generic_top','"W=4"','-generic_top','"H=3"')},
              @{Name='tb_dpc_window_blocked'; Snapshot='tb_dpc_window_blocked';
                Pattern='DPC_BLOCKED_START_PASS'; Generics=@()},
              @{Name='tb_dpc_dynamic'; Snapshot='tb_dpc_dynamic_quick'; Pattern='DPC_DYNAMIC_PASS'; Generics=@()})
    if ($Full) {
        $runs += @{Name='tb_dpc_dynamic'; Snapshot='tb_dpc_dynamic_full'; Pattern='DPC_DYNAMIC_PASS';
                   Generics=@('-generic_top','"W=1280"','-generic_top','"H=1024"')}
    }
    foreach ($run in $runs) {
        & "$bin/xelab.bat" $run.Name @($run.Generics) -s $run.Snapshot
        if ($LASTEXITCODE) { throw "$($run.Snapshot) elaboration failed" }
        & "$bin/xsim.bat" $run.Snapshot -runall 2>&1 | Tee-Object "$($run.Snapshot).log"
        if ($LASTEXITCODE -or !(Select-String "$($run.Snapshot).log" -Pattern $run.Pattern) -or
            (Select-String "$($run.Snapshot).log" -Pattern 'Fatal:|ERROR:')) {
            throw "$($run.Snapshot) simulation failed"
        }
    }
} finally { Pop-Location }
