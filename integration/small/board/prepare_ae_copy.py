"""Snapshot AE sources into this repository's build directory; never edit source AE."""
import argparse, subprocess, sys
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--ae-source', default='E:/workspace/AI_Projects/ZU4EV/zynq-zu4ev_platform')
p.add_argument('--destination', type=Path, help='New isolated output directory; must not exist')
a=p.parse_args()
repo=Path(__file__).resolve().parents[3]
source=Path(a.ae_source).resolve()
dest=a.destination.resolve() if a.destination else repo/'build/ibex_small/ae_board'
subprocess.run([sys.executable,str(source/'tools/package_full_ae_project.py'),'--source',str(source),'--destination',str(dest)],check=True)
top=dest/'rtl/camera_top.v'
s=top.read_text(encoding='utf-8')
assert s.count('endmodule')==1
s=s.replace('endmodule','    ibex_board_debug ibex_debug_i (.clk_i(lite_clk), .locked_i(locked), .video_clk_i(video_clk), .video_rst_ni(rx_video_resetn), .isp_stats_i(ibex_isp_stats), .isp_fe_seq_i(ae_fe_seq), .isp_sof_seq_i(ae_sof_seq));\nendmodule')
top.write_text(s,encoding='utf-8')
print('Snapshot ISP statistics ports added; source_manifest records original hashes.')

# Explicit ports in the isolated snapshot; original sources remain untouched.
def patch(path, old, new):
    text=path.read_text(encoding='utf-8')
    if text.count(old)!=1:
        raise RuntimeError(f'{path}: expected unique integration anchor {old!r}')
    path.write_text(text.replace(old,new),encoding='utf-8')
patch(top, '    isp #(', '    wire [511:0] ibex_isp_stats;\n    isp #(')
patch(top, ')) isp (', ')) isp (.ibex_stats_o(ibex_isp_stats),')
isp=dest/'isp/isp.v'
patch(isp, 'module isp #(', 'module isp #(') # validate expected module family
text=isp.read_text(encoding='utf-8')
# Insert a port at the first module port list following parameters.
import re
m=re.search(r'\)\s*\(',text)
if not m: raise RuntimeError('isp module parameter/port boundary missing')
text=text[:m.end()]+'output wire [511:0] ibex_stats_o,\n'+text[m.end():]
isp.write_text(text,encoding='utf-8')
patch(isp, ')) converter (', ')) converter (.ibex_stats_o(ibex_stats_o),')
frontend=dest/'isp/isp_capture_frontend.sv'
patch(frontend, ' input wire [15:0] isp_axi_awaddr,', ' output wire [511:0] ibex_stats_o,\n input wire [15:0] isp_axi_awaddr,')
patch(frontend, '  wire [47:0] ae_sum;', "  wire [47:0] ae_sum;\n  assign ibex_stats_o={ae_height,ae_width,ae_y,ae_x,ae_overrun,ae_bad,{20'b0,ae_result_black,ae_result_region},{29'b0,ae_active,ae_busy,ae_valid},16'b0,ae_sum,ae_count,ae_mean,ae_frame,ae_seq,64'b0};")
patch(frontend, ' end else begin: no_control', " end else begin: no_control\n  assign ibex_stats_o=512'b0;")

# Place the gate in the ISP video clock domain, downstream of the PS clock
# converter already present in the platform block design. No source AE edits.
axi_channels = [('awaddr', 16, 1), ('awvalid', 1, 1), ('awready', 1, 0), ('wdata', 32, 1), ('wstrb', 4, 1), ('wvalid', 1, 1), ('wready', 1, 0), ('bresp', 2, 0), ('bvalid', 1, 0), ('bready', 1, 1), ('araddr', 16, 1), ('arvalid', 1, 1), ('arready', 1, 0), ('rdata', 32, 0), ('rresp', 2, 0), ('rvalid', 1, 0), ('rready', 1, 1)]
text = top.read_text(encoding='utf-8')
start = text.index(')) isp (')
end = text.index('    );', start)
block = text[start:end]
for name, width, direction in axi_channels:
    expression = f'isp_axi_{name}' + ('[15:0]' if name in ('awaddr','araddr') else '')
    old = f'.isp_axi_{name}({expression})'
    if block.count(old) != 1:
        raise RuntimeError(f'ISP AXI integration anchor missing: {old}')
    block = block.replace(old, f'.isp_axi_{name}(shared_isp_axi_{name})')
block = block.replace('.ibex_stats_o(ibex_isp_stats)', '.ibex_stats_o(ibex_isp_stats), .ibex_cfg_reset_ni(ibex_cfg_resetn)')
text = text[:start] + block + text[end:]
declarations = '    wire ibex_cfg_resetn;\n'
for prefix in ('cpu_isp_axi_', 'shared_isp_axi_'):
    for name, width, direction in axi_channels:
        declarations += f"    wire {f'[{width-1}:0] ' if width>1 else ''}{prefix}{name};\n"
connections = ['.clk_i(video_clk)', '.rst_ni(ibex_cfg_resetn)']
for name, width, direction in axi_channels:
    ps_expression = f'isp_axi_{name}' + ('[15:0]' if name in ('awaddr','araddr') else '')
    connections += [f'.ps_axi_{name}({ps_expression})',
                    f'.cpu_axi_{name}(cpu_isp_axi_{name})',
                    f'.m_axi_{name}(shared_isp_axi_{name})']
gate = declarations + '    ibex_isp_cfg_owner ibex_isp_owner_i (\n        ' + ',\n        '.join(connections) + ');\n'
text = text.replace('    wire [511:0] ibex_isp_stats;', gate + '    wire [511:0] ibex_isp_stats;')
anchor = '.isp_sof_seq_i(ae_sof_seq));'
replacement = '.isp_sof_seq_i(ae_sof_seq), .isp_cfg_rst_ni(uvc_resetn), .cfg_reset_no(ibex_cfg_resetn), ' + ', '.join(f'.m_isp_axi_{n}(cpu_isp_axi_{n})' for n,w,d in axi_channels) + ');'
if text.count(anchor)!=1: raise RuntimeError('Ibex config port integration anchor missing')
text = text.replace(anchor,replacement)
top.write_text(text,encoding='utf-8')
print('Real ISP register path connected through video-domain ownership gate.')

# Coordinate only the AXI register reset with the Ibex bridge. Leave the
# camera/video pipeline reset and sensor initialization behavior unchanged.
patch(isp, 'output wire [511:0] ibex_stats_o,',
      'output wire [511:0] ibex_stats_o, input wire ibex_cfg_reset_ni,')
patch(isp, '.ibex_stats_o(ibex_stats_o),',
      '.ibex_stats_o(ibex_stats_o), .ibex_cfg_reset_ni(ibex_cfg_reset_ni),')
patch(frontend, ' output wire [511:0] ibex_stats_o,',
      ' output wire [511:0] ibex_stats_o, input wire ibex_cfg_reset_ni,')
patch(frontend, '.clk(clk),.resetn(resetn),.s_axi_awaddr(isp_axi_awaddr)',
      '.clk(clk),.resetn(ibex_cfg_reset_ni),.s_axi_awaddr(isp_axi_awaddr)')

# Sensor master exists only in this isolated source tree. The same IOBUFs
# preserve physical pins; each owner can pull low or release, never drive high.
soc=dest/'rtl/soc/soc_subsystem.v'
patch(soc, '    output wire camera_sda_sample\n',
      '    output wire camera_sda_sample,\n'
      '    input wire ibex_sensor_grant, ibex_sensor_scl_low, ibex_sensor_sda_low,\n'
      '    output wire ps_sensor_scl_release, ps_sensor_sda_release\n')
patch(soc, '    IOBUF iic_scl_buf (.I(iic_scl_o), .IO(camera_scl), .O(iic_scl_i), .T(iic_scl_t));',
      "    assign ps_sensor_scl_release = iic_scl_t | iic_scl_o;\n"
      "    IOBUF iic_scl_buf (.I(1'b0), .IO(camera_scl), .O(iic_scl_i), .T(ibex_sensor_grant ? ~ibex_sensor_scl_low : ps_sensor_scl_release));")
patch(soc, '    IOBUF iic_sda_buf (.I(iic_sda_o), .IO(camera_sda), .O(iic_sda_i), .T(iic_sda_t));',
      "    assign ps_sensor_sda_release = iic_sda_t | iic_sda_o;\n"
      "    IOBUF iic_sda_buf (.I(1'b0), .IO(camera_sda), .O(iic_sda_i), .T(ibex_sensor_grant ? ~ibex_sensor_sda_low : ps_sensor_sda_release));")
patch(top, '    wire ibex_cfg_resetn;',
      '    wire ibex_sensor_owner, ibex_sensor_run, ibex_sensor_stop, ibex_sensor_grant;\n'
      '    wire ibex_sensor_scl_low, ibex_sensor_sda_low;\n'
      '    wire ps_sensor_scl_release, ps_sensor_sda_release;\n'
      '    wire [31:0] ibex_sensor_status;\n    wire ibex_cfg_resetn;')
patch(top, '    ibex_isp_cfg_owner ibex_isp_owner_i (',
      "    ibex_isp_cfg_owner #(.EnableSensorOwnership(1'b1)) ibex_isp_owner_i (\n"
      '        .sensor_status_async_i(ibex_sensor_status), .owner_o(ibex_sensor_owner), .run_o(ibex_sensor_run), .stop_o(ibex_sensor_stop),')
patch(top, '        .camera_scl_sample(camera_scl_sample),',
      '        .camera_scl_sample(camera_scl_sample),\n'
      '        .ibex_sensor_grant(ibex_sensor_grant),\n'
      '        .ibex_sensor_scl_low(ibex_sensor_scl_low), .ibex_sensor_sda_low(ibex_sensor_sda_low),\n'
      '        .ps_sensor_scl_release(ps_sensor_scl_release), .ps_sensor_sda_release(ps_sensor_sda_release),')
patch(top, '.isp_cfg_rst_ni(uvc_resetn),',
      '.sensor_owner_i(ibex_sensor_owner), .sensor_run_i(ibex_sensor_run), .sensor_stop_i(ibex_sensor_stop), '
      '.sensor_ps_scl_release_i(ps_sensor_scl_release), .sensor_ps_sda_release_i(ps_sensor_sda_release), '
      '.sensor_scl_i(camera_scl_sample), .sensor_sda_i(camera_sda_sample), '
      '.sensor_scl_low_o(ibex_sensor_scl_low), .sensor_sda_low_o(ibex_sensor_sda_low), '
      '.sensor_grant_o(ibex_sensor_grant), .sensor_status_o(ibex_sensor_status), .isp_cfg_rst_ni(uvc_resetn),')

# The upstream hardware packager omits Linux runtime software. Copy its bounded
# source subtree here, including the already tested USB DMA-BUF broker and tests.
import hashlib, json, shutil
manifest=json.loads((dest/'source_manifest.json').read_text(encoding='utf-8'))
known={entry['path'] for entry in manifest['files']}
excluded={'build','__pycache__','.git','.Xil','reports','dist'}
for original in sorted((source/'software').rglob('*')):
    relative=original.relative_to(source)
    if any(part in excluded for part in relative.parts) or not original.is_file():
        continue
    if original.suffix.lower() not in {'.c','.h','.sh','.py','.md','.ld','.tcl','.json','.dts','.dtsi','.bb','.bbappend'} and original.name!='Makefile':
        continue
    if relative.as_posix() in known:
        continue
    if original.is_symlink():
        raise RuntimeError(f'Symlink source unsupported: {original}')
    target=dest/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    content=original.read_bytes()
    target.write_bytes(content)
    digest=hashlib.sha256(content).hexdigest()
    manifest['files'].append({'path':relative.as_posix(),'original_path':str(original),
        'source_sha256':digest,'snapshot_sha256':digest,'bytes':len(content)})
# Add the Ibex runtime host utility, maintained in this repository.
host=repo/'integration/small/tools/ibex_isp_handoff.c'
shutil.copy2(host,dest/'software/ibex_isp_handoff.c')
makefile=dest/'software/Makefile'
with makefile.open('a',encoding='utf-8') as out:
    out.write('\nall: $(OUT)/ibex_isp_handoff\n$(OUT)/ibex_isp_handoff: ibex_isp_handoff.c | $(OUT)\n\t$(CC) $(CFLAGS) $< $(LDFLAGS) -o $@\n')
manifest['ibex_integration']={'repository':str(repo),'sensor_control':'native 0x52000000',
    'ps_handoff':'ISP+ff00/ff04/ff08','runtime':'software/Makefile',
    'patched_paths':['rtl/camera_top.v','rtl/soc/soc_subsystem.v','isp/isp.v','isp/isp_capture_frontend.sv','software/Makefile']}
(dest/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
shutil.copy2(repo/'integration/small/board/ISP_MASTER.md',dest/'IBEX_ISP_MASTER.md')
# Correct the source README's earlier copy-default description in this bundle.
software_readme=dest/'software/README.md'
readme=software_readme.read_text(encoding='utf-8')
# Remove the obsolete diagnostic paragraph by stable ASCII markers; avoid
# depending on the source README's locale-specific prose.
lines=readme.splitlines()
lines=[line for line in lines if not line.startswith('`--profile-static-usb`')]
readme='\n'.join(lines)+'\n\n'
readme+=('## Current Ibex bundle USB behavior\n\n'
    'Normal USB streaming shares capture DMA-BUFs by default. Capture buffers '
    'remain held until both DP and USB complete. `--usb-sequence-marker` and '
    '`--profile-static-usb` retain the copy path for diagnostics. Static mode '
    'does not validate live camera throughput and must not be enabled for production.\n')
assert not any(line.startswith('`--profile-static-usb`') for line in readme.splitlines())
software_readme.write_text(readme,encoding='utf-8')
ibex_inputs=[host,repo/'integration/small/tools/build_ae_live.sh',repo/'integration/small/board/prepare_ae_copy.py',
    repo/'integration/small/board/build_ae_board.tcl',repo/'integration/small/board/ibex_board_debug.sv']
ibex_inputs+=list((repo/'integration/small/rtl').glob('*.sv'))
firmware=dest/'software/ibex-ae'
firmware.mkdir()
for original in sorted((repo/'integration/small/ae_live/ibex').iterdir()):
    if original.is_file():
        shutil.copy2(original,firmware/original.name)
        ibex_inputs.append(original)
for name in ('ae_core.c','ae_core.h'):
    original=repo/'integration/small/ae_live'/name
    shutil.copy2(original,firmware/name)
    ibex_inputs.append(original)
# Standalone firmware rebuild inside the source bundle.
(firmware/'build.sh').write_text("""#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
prefix=${RISCV_PREFIX:-riscv64-unknown-elf-}
out=${1:-build}
mkdir -p "$out"
"${prefix}gcc" -Os -march=rv32imc_zicsr -mabi=ilp32 -msmall-data-limit=0 -Wall -Wextra -Werror -ffreestanding -fno-builtin -nostdlib -nostartfiles -Wl,--build-id=none,-Map,"$out/ae_live.map" -T link.ld -I. start.S main.c runtime.c ae_core.c -lgcc -o "$out/ae_live.elf"
"${prefix}objcopy" -O binary "$out/ae_live.elf" "$out/ae_live.bin"
python3 bin_to_mem.py "$out/ae_live.bin" "$out/ae_live.mem"
"${prefix}size" "$out/ae_live.elf"
""",encoding='utf-8',newline='\n')
shutil.copy2(repo/'integration/small/tools/bin_to_mem.py',firmware/'bin_to_mem.py')
ibex_inputs.append(repo/'integration/small/tools/bin_to_mem.py')
patched=manifest['ibex_integration']['patched_paths']+[
    'software/README.md','software/ibex_isp_handoff.c','IBEX_ISP_MASTER.md']
patched += [path.relative_to(dest).as_posix() for path in firmware.iterdir()]
final_manifest={'format':1,'scope':'Final source integration; build reports establish tool execution',
    'patched_files':[{'path':relative,'sha256':hashlib.sha256((dest/relative).read_bytes()).hexdigest()} for relative in patched],
    'ibex_inputs':[{'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(set(ibex_inputs))]}
(dest/'integration_manifest.json').write_text(json.dumps(final_manifest,indent=2)+'\n',encoding='utf-8')
print('Native sensor mux, PS runtime handoff and USB shared DMA-BUF sources integrated.')
