#!/usr/bin/env python3
"""UART recorder and explicit command inbox for RAM-only board validation."""
import argparse,pathlib,serial,time
p=argparse.ArgumentParser();p.add_argument('--directory',required=True);p.add_argument('--port',default='COM13');a=p.parse_args()
root=pathlib.Path(a.directory).resolve();root.mkdir(parents=True,exist_ok=True)
inbox=root/'commands.txt';inbox.touch(exist_ok=True);offset=inbox.stat().st_size
stop=root/'stop.request'
if stop.exists():raise SystemExit('stop.request exists; monitor not started')
with serial.Serial(a.port,115200,timeout=.03) as port, (root/'uart.log').open('ab',buffering=0) as log:
 print('SERIAL_READY '+a.port,flush=True)
 while not stop.exists():
  data=port.read(65536)
  if data:log.write(data)
  with inbox.open('rb') as commands:
   commands.seek(offset);chunk=commands.read(48)
  if chunk:port.write(chunk);port.flush();offset+=len(chunk)
  time.sleep(.01)
print('SERIAL_CLOSED',flush=True)
