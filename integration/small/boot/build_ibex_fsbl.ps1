param(
 [Parameter(Mandatory=$true)][string]$Platform,
 [Parameter(Mandatory=$true)][string]$BuildDirectory,
 [switch]$RamTest,
 [string]$Driver='D:/Xilinx/2025.1/data/embeddedsw/XilinxProcessorIPLib/drivers/iicps_v3_21/src',
 [string]$Compiler='D:/Xilinx/2025.1/gnu/aarch64/nt/aarch64-none/bin/aarch64-none-elf-gcc.exe'
)
$ErrorActionPreference='Stop'
$platformRoot=(Resolve-Path -LiteralPath $Platform).Path
$build=[IO.Path]::GetFullPath($BuildDirectory)
if($build.StartsWith($platformRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Original platform is read-only'}
$prepared=Join-Path $build 'source'
$arguments=@('--platform',$platformRoot,'--driver',$Driver,'--output',$prepared)
if($RamTest){$arguments+='--ram-test'}
python "$PSScriptRoot/prepare_ibex_fsbl.py" @arguments
if($LASTEXITCODE -ne 0){throw 'Isolated FSBL preparation failed'}
$bsp=Join-Path $platformRoot 'firmware/boot_reference/zynqmp_fsbl/zynqmp_fsbl_bsp/psu_cortexa53_0'
$flags=@('-DARMA53_64','-DFSBL_DEBUG_INFO','-Os','-flto','-ffat-lto-objects','-ffunction-sections','-fdata-sections','-Wall',"-I$bsp/include","-I$prepared")
if($RamTest){$flags+='-DSC130_RAM_BOOT_TEST'}
$objects=@()
foreach($source in (Get-ChildItem -LiteralPath $prepared -File | Where-Object {$_.Extension -in '.c','.S'})){
 $obj=Join-Path $build ($source.BaseName+'.o')
 & $Compiler @flags -c $source.FullName -o $obj
 if($LASTEXITCODE -ne 0){throw "FSBL compile failed: $source"}
 $objects+=$obj
}
$elf=Join-Path $build 'fsbl_sc130.elf'
$map=Join-Path $build 'fsbl.map'
& $Compiler @flags @objects "-L$bsp/lib" "-T$prepared/lscript.ld" '-Wl,--start-group' -lxil -lxilffs -lxilsecure -lxilpm -lgcc -lc '-Wl,--end-group' -n '-Wl,--gc-sections' "-Wl,-Map=$map" -o $elf
if($LASTEXITCODE -ne 0){throw 'FSBL link failed'}
python "$platformRoot/boot/fsbl/check_layout.py" $map
if($LASTEXITCODE -ne 0){throw 'FSBL OCM check failed'}
$toolRoot=Split-Path $Compiler
& "$toolRoot/aarch64-none-elf-readelf.exe" -h -l $elf | Set-Content (Join-Path $build 'elf-layout.txt')
& "$toolRoot/aarch64-none-elf-nm.exe" $elf | Set-Content (Join-Path $build 'symbols.txt')
Get-FileHash -Algorithm SHA256 -LiteralPath $elf
Write-Output "IBEX_FSBL_BUILD_PASS ram_test=$RamTest $elf"
