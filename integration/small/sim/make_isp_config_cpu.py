"""Regenerate the RV32I ISP configuration integration-test ROM."""
from pathlib import Path

def lui(rd, imm): return (imm << 12) | (rd << 7) | 0x37
def addi(rd, rs, imm): return ((imm & 0xfff) << 20) | (rs << 15) | (rd << 7) | 0x13
def lw(rd, rs, imm): return ((imm & 0xfff) << 20) | (rs << 15) | (2 << 12) | (rd << 7) | 3
def store(rs2, rs1, imm, funct):
    return (((imm >> 5) & 127) << 25) | (rs2 << 20) | (rs1 << 15) | (funct << 12) | ((imm & 31) << 7) | 0x23

# Result words in RAM: ISP ID, applied mode, AE black, snapshot word, done.
p = [lui(8, 0x51000), lui(9, 0x200), lw(10, 8, 0), store(10, 9, 0, 2),
     addi(10, 0, 2), store(10, 8, 0x10, 2), addi(10, 0, 1),
     store(10, 8, 0x20, 2), lw(10, 8, 0x34), store(10, 9, 4, 2),
     addi(10, 0, 0x57), store(10, 8, 0x20c, 0), lw(10, 8, 0x20c),
     store(10, 9, 8, 2), lui(8, 0x50000), lw(10, 8, 0),
     store(10, 9, 12, 2), addi(10, 0, 0x55), store(10, 9, 16, 2), 0x6f]
Path(__file__).with_name('isp_config_cpu.mem').write_text(''.join(f'{w:08x}\n' for w in [0] * 32 + p))
