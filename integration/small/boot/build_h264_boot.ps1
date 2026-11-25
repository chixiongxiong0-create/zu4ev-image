param(
 [Parameter(Mandatory=$true)][string]$Bitstream,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [string]$Baseline='E:/workspace/AI_Projects/RISC_V/ibex/build/ibex_small/qspi_v3_20261031',
 [string]$Bootgen='D:/Xilinx/2025.1/Vitis/bin/bootgen.bat'
)
$ErrorActionPreference='Stop'
$bit=(Resolve-Path -LiteralPath $Bitstream).Path
$out=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $out){throw 'Output must be a new directory'}
New-Item -ItemType Directory -Path $out | Out-Null
foreach($variant in @('production','ramtest')){
 $seed=Join-Path $Baseline $variant
 $manifest=Get-Content -Raw -LiteralPath (Join-Path $seed 'boot-inputs.json') | ConvertFrom-Json
 $dest=Join-Path $out $variant
 $inputs=Join-Path $dest 'inputs'
 New-Item -ItemType Directory -Path $inputs -Force | Out-Null
 $records=@()
 foreach($item in $manifest){
  $source=if($item.name -eq 'camera_top.bit'){$bit}else{Join-Path (Join-Path $seed 'inputs') $item.name}
  if($item.name -ne 'camera_top.bit'){
   $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
   if($hash -ne $item.sha256 -or (Get-Item -LiteralPath $source).Length -ne $item.bytes){throw "Baseline input mismatch: $source"}
  }
  $target=Join-Path $inputs $item.name
  Copy-Item -LiteralPath $source -Destination $target
  $records+=@{name=$item.name;source=$source;bytes=(Get-Item -LiteralPath $target).Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()}
 }
 $paths=@('fsbl_sc130.elf','pmufw.elf','camera_top.bit','bl31.elf','u-boot.elf') | ForEach-Object {(Join-Path $inputs $_).Replace('\','/')}
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
 $records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dest 'boot-inputs.json') -Encoding utf8
}
Write-Output "H264_BOOT_PACKAGE_PASS $out"
