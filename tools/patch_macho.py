#!/usr/bin/env python3
"""Inject one weak dylib load command into verified zero header padding, without moving code.

This intentionally rejects encrypted or signed executables. It does not decrypt,
bypass protection, shift sections, rewrite chained fixups, or fabricate signing.
"""
import argparse, hashlib, json, pathlib, struct
DYLIB='@executable_path/Frameworks/AureaCraft.dylib'

def commands(data: bytes) -> list[dict]:
    if len(data)<32:raise ValueError('Truncated Mach-O header')
    magic,cpu,subtype,kind,ncmds,size,flags,reserved=struct.unpack_from('<8I',data)
    if magic!=0xfeedfacf or cpu!=0x100000c or kind!=2:
        raise ValueError('Expected a thin arm64 Mach-O executable')
    if ncmds>4096 or 32+size>len(data):raise ValueError('Invalid load-command table')
    result=[];off=32
    for _ in range(ncmds):
        if off+8>32+size:raise ValueError('Truncated load command')
        cmd,length=struct.unpack_from('<II',data,off)
        if length<8 or length%8 or off+length>32+size:raise ValueError('Invalid command length')
        entry={'cmd':cmd,'offset':off,'size':length}
        if cmd in (0xc,0x80000018,0x8000001f,0x80000023):
            if length<24:raise ValueError('Truncated dylib command')
            nameoff=struct.unpack_from('<I',data,off+8)[0]
            if not 24<=nameoff<length:raise ValueError('Invalid dylib name')
            value=data[off+nameoff:off+length].split(b'\0',1)[0]
            entry['name']=value.decode('utf-8',errors='strict')
        result.append(entry);off+=length
    if off!=32+size:raise ValueError('Load-command count and size disagree')
    return result

def inject(data: bytes) -> tuple[bytes, dict]:
    cmds=commands(data)
    for cmd in cmds:
        if cmd['cmd']==0x1d:raise ValueError('Signed executable: remove signing with the authorized signing tool first')
        if cmd['cmd'] in (0x21,0x2c):
            if cmd['size']<20:raise ValueError('Truncated encryption information')
            if struct.unpack_from('<I',data,cmd['offset']+16)[0]:raise ValueError('Encrypted executable is not supported')
    existing=[c for c in cmds if c.get('name')==DYLIB]
    if existing:
        if len(existing)!=1 or existing[0]['cmd']!=0x80000018:raise ValueError('Conflicting existing extension load command')
        return data,{'already_patched':True,'command_offset':existing[0]['offset'],'command_size':existing[0]['size']}
    sections=[]
    for cmd in cmds:
        if cmd['cmd']!=0x19:continue
        off=cmd['offset'];length=cmd['size']
        if length<72:raise ValueError('Truncated segment command')
        count=struct.unpack_from('<I',data,off+64)[0]
        if 72+80*count!=length:raise ValueError('Invalid segment section count')
        for i in range(count):
            p=off+72+i*80
            section_size=struct.unpack_from('<Q',data,p+40)[0]
            file_offset=struct.unpack_from('<I',data,p+48)[0]
            typ=struct.unpack_from('<I',data,p+64)[0]&0xff
            if file_offset and section_size and typ not in (1,0xc,0x12):
                if file_offset+section_size>len(data):raise ValueError('Section lies outside file')
                sections.append(file_offset)
    if not sections:raise ValueError('No file-backed sections found')
    first=min(sections);ncmds,size=struct.unpack_from('<II',data,16);end=32+size
    name=DYLIB.encode()+b'\0';length=(24+len(name)+7)&~7
    if first<end+length:raise ValueError('Insufficient header padding; refusing to relocate code')
    if any(data[end:end+length]):raise ValueError('Header padding is not zero; refusing to overwrite')
    payload=struct.pack('<6I',0x80000018,length,24,0,0x10000,0x10000)+name
    payload=payload.ljust(length,b'\0')
    out=bytearray(data);out[end:end+length]=payload;struct.pack_into('<II',out,16,ncmds+1,size+length)
    final=bytes(out);commands(final)
    if final[:16]!=data[:16] or final[24:end]!=data[24:end] or final[end+length:]!=data[end+length:]:raise AssertionError('Unexpected executable mutation')
    return final,{'already_patched':False,'command_offset':end,'command_size':length,'first_section':first,'padding_before':first-end,'load_commands_before':ncmds,'load_commands_after':ncmds+1,'dylib':DYLIB,'original_sha256':hashlib.sha256(data).hexdigest(),'patched_sha256':hashlib.sha256(final).hexdigest()}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('input',type=pathlib.Path);p.add_argument('output',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path);args=p.parse_args()
    if args.input.resolve()==args.output.resolve():p.error('Use a different output path to preserve the original')
    out,report=inject(args.input.read_bytes());args.output.write_bytes(out);args.output.chmod(0o755)
    text=json.dumps(report,indent=2)+'\n';print(text,end='')
    if args.report:args.report.write_text(text)
