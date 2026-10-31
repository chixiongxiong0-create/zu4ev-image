param(
 [string]$Platform='E:/workspace/AI_Projects/ZU4EV/zynq-zu4ev_platform',
 [string]$Bundle='E:/workspace/AI_Projects/RISC_V/ibex/build/ibex_small/isp_master_v3_20261030',
 [string]$OutputDirectory='E:/workspace/AI_Projects/RISC_V/ibex/build/ibex_small/qspi_v3_20261031',
 [string]$Bootgen='D:/Xilinx/2025.1/Vitis/bin/bootgen.bat'
)
$ErrorActionPreference='Stop'
$platformRoot=(Resolve-Path -LiteralPath $Platform).Path
$bundleRoot=(Resolve-Path -LiteralPath $Bundle).Path
$out=[IO.Path]::GetFullPath($OutputDirectory)
if($out.StartsWith($platformRoot,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($bundleRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be independent of original/frozen sources'}
New-Item -ItemType Directory -Force -Path $out | Out-Null
function LinuxPath([string]$Path){
 $value=& wsl -e wslpath -u ([IO.Path]::GetFullPath($Path))
 if($LASTEXITCODE -ne 0){throw 'wslpath failed'}
 return $value.Trim()
}
foreach($variant in @('production','ramtest')){
 $arguments=@{Platform=$platformRoot;BuildDirectory=(Join-Path $out "fsbl-$variant")}
 if($variant -eq 'ramtest'){$arguments.RamTest=$true}
 & "$PSScriptRoot/build_ibex_fsbl.ps1" @arguments *> (Join-Path $out "fsbl-$variant-build.log")
}
$helper=Join-Path $out 'ibex_iic_prepare'
& wsl -e aarch64-linux-gnu-gcc -O2 -std=c11 -Wall -Wextra -Werror -static (LinuxPath "$PSScriptRoot/ibex_iic_prepare.c") -o (LinuxPath $helper)
if($LASTEXITCODE -ne 0){throw 'Linux IIC helper build failed'}
foreach($variant in @('production','ramtest')){
 $dest=Join-Path $out $variant
 $inputs=Join-Path $dest 'inputs'
 New-Item -ItemType Directory -Force -Path $inputs | Out-Null
 $uBootName=if($variant -eq 'ramtest'){'u-boot-ramtest.elf'}else{'u-boot.elf'}
 $sources=@((Join-Path $out "fsbl-$variant/fsbl_sc130.elf"),
            (Join-Path $platformRoot 'boot/prebuilt/pmufw.elf'),
            (Join-Path $bundleRoot 'deliverables/camera_top.bit'),
            (Join-Path $platformRoot 'boot/prebuilt/bl31.elf'),
            (Join-Path $platformRoot "boot/prebuilt/$uBootName"))
 $names=@('fsbl_sc130.elf','pmufw.elf','camera_top.bit','bl31.elf','u-boot.elf')
 $manifest=@()
 for($i=0;$i -lt $sources.Count;$i++){
  $target=Join-Path $inputs $names[$i]
  Copy-Item -LiteralPath $sources[$i] -Destination $target -Force
  $manifest+=@{name=$names[$i];source=$sources[$i];bytes=(Get-Item -LiteralPath $target).Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()}
 }
 $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $dest 'boot-inputs.json') -Encoding utf8
 $paths=@($names | ForEach-Object {(Join-Path $inputs $_).Replace('\','/')})
 $bif=@"
the_ROM_image:
{
 [bootloader, destination_cpu=a53-0] "$($paths[0])"
 [pmufw_image] "$($paths[1])"
 [destination_device=pl] "$($paths[2])"
 [destination_cpu=a53-0, exception_level=el-3, trustzone] "$($paths[3])"
 [destination_cpu=a53-0, exception_level=el-2] "$($paths[4])"
}
"@
 $bifPath=Join-Path $dest 'boot.bif'
 [IO.File]::WriteAllText($bifPath,$bif,[Text.UTF8Encoding]::new($false))
 & $Bootgen -arch zynqmp -image $bifPath -o (Join-Path $dest 'BOOT.BIN') -w on *> (Join-Path $dest 'bootgen.log')
 if($LASTEXITCODE -ne 0){throw "Bootgen failed: $variant"}
 & wsl -e python3 -B (LinuxPath "$PSScriptRoot/package_ibex_qspi.py") `
  --reference (LinuxPath "$platformRoot/firmware/linux") `
  --boot-source (LinuxPath "$platformRoot/boot/prebuilt") `
  --software (LinuxPath "$bundleRoot/deliverables") `
  --iic-helper (LinuxPath $helper) --output (LinuxPath $dest) *> (Join-Path $dest 'package.log')
 if($LASTEXITCODE -ne 0){throw "FIT/QSPI packaging failed: $variant; see package.log"}
}
Write-Output "IBEX_QSPI_OFFLINE_BUILD_PASS $out"
Write-Output 'Hardware RAM boot and flash verification are separate; this script never accesses hardware.'
