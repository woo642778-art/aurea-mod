#!/usr/bin/env python3
"""Locally package the exact authorized Aurea IPA; never upload its bytes.

No signing identity is fabricated. The result must be re-signed for installation.
Original files remain byte-identical except the main Mach-O header and Info.plist.
"""
import argparse, copy, hashlib, json, os, pathlib, plistlib, stat, struct, tempfile, zipfile
from patch_macho import inject, commands, DYLIB
ORIGINAL_SHA='5ee854532ff022281129f36d414553e507f69c930ce305c6191a8c2829c31d14'
RUNTIME_SHA='b922abeda2420391a7fd887f53ebae6948730e63720bad6a6eb3dc48dc1b46a8'
ROOT='Payload/Aurea.app/'

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def safe_archive_name(name: str) -> bool:
    if not name or name.startswith('/') or '\\' in name or '\0' in name:return False
    return all(x not in ('','.','..') for x in name.rstrip('/').split('/'))

def validate_dylib(data: bytes) -> dict:
    if len(data)<32:raise ValueError('Truncated dylib')
    magic,cpu,subtype,kind,count,size,flags,reserved=struct.unpack_from('<8I',data)
    if magic!=0xfeedfacf or cpu!=0x100000c or kind!=6:raise ValueError('Expected a thin ARM64 Mach-O dylib')
    if count>4096 or size+32>len(data):raise ValueError('Invalid dylib command table')
    off=32;version=None
    for _ in range(count):
        if off+8>32+size:raise ValueError('Truncated dylib load command')
        cmd,length=struct.unpack_from('<II',data,off)
        if length<8 or length%8 or off+length>32+size:raise ValueError('Invalid dylib command length')
        if cmd==0x32:
            if length<24:raise ValueError('Truncated build version')
            platform,minimum,sdk,tools=struct.unpack_from('<4I',data,off+8)
            if platform!=2 or minimum>0x100300:raise ValueError('Dylib is not compatible with device iOS 16.3')
            version={'platform':platform,'minimum_os_encoded':minimum,'sdk_encoded':sdk}
        off+=length
    if off!=32+size or version is None:raise ValueError('Missing or inconsistent iOS build version')
    return version

def zip_entry(name: str, mode: int=0o644) -> zipfile.ZipInfo:
    i=zipfile.ZipInfo(name,date_time=(2026,10,16,0,0,0));i.create_system=3
    i.external_attr=(stat.S_IFREG|mode)<<16;i.compress_type=zipfile.ZIP_DEFLATED
    return i

def package(original: pathlib.Path, dylib: pathlib.Path, runtime: pathlib.Path,
            integration: pathlib.Path, upstream: pathlib.Path, output: pathlib.Path) -> dict:
    original,dylib,runtime,integration,upstream,output=[p.resolve() for p in (original,dylib,runtime,integration,upstream,output)]
    if output.exists():raise ValueError('Output already exists; use a new filename to preserve previous builds')
    if output in (original,dylib,runtime):raise ValueError('Output conflicts with an input')
    if sha(original.read_bytes())!=ORIGINAL_SHA:raise ValueError('Original IPA does not match the analyzed build')
    if sha(runtime.read_bytes())!=RUNTIME_SHA:raise ValueError('EffectCraft runtime digest mismatch')
    lib=dylib.read_bytes();platform=validate_dylib(lib)
    additions={ROOT+'Frameworks/AureaCraft.dylib':(lib,0o755)}
    runtime_hashes={}
    with zipfile.ZipFile(runtime) as z:
        if len(z.namelist())!=len(set(z.namelist())):raise ValueError('Duplicate runtime entries')
        for i in z.infolist():
            if not safe_archive_name(i.filename):raise ValueError('Unsafe runtime ZIP path')
            if i.is_dir():continue
            p=pathlib.PurePosixPath(i.filename)
            if p.parts[0]!='effectcraft-web-0.10.0':raise ValueError('Unexpected runtime root')
            name=ROOT+'AureaCraft/'+'/'.join(p.parts[1:]);data=z.read(i)
            additions[name]=(data,0o644);runtime_hashes[name]=sha(data)
    for name in ('core.mjs','studio.mjs','studio.html','studio.css'):
        key=ROOT+'AureaCraft/'+name
        if key in additions:raise ValueError('Integration would overwrite upstream runtime')
        additions[key]=((integration/'web'/name).read_bytes(),0o644)
    for name in ('NOTICE','ATTRIBUTION.md'):
        additions[ROOT+'AureaCraft/'+name]=((upstream/name).read_bytes(),0o644)
    additions[ROOT+'AureaCraft/LICENSE-AUREA-STUDIO']=((integration/'LICENSE').read_bytes(),0o644)
    provenance={'integration':'0.1.0-experimental','effectcraft_release':'v0.10.0',
      'effectcraft_release_commit':'05955c08b4fd025f1a09882df72e6dbff1a8148a',
      'effectcraft_runtime_zip_sha256':RUNTIME_SHA,'source_audit_commit':'7c733f4cc9043f011a5f87ef6a83d18c8fb6aa3b',
      'original_ipa_sha256':ORIGINAL_SHA,'extension_sha256':sha(lib),
      'integration_mode':'offline-WASM-workspace-and-additive-media-bridge','native_effect_parity':False,
      'requires_resigning':True,'physical_device_tested':False}
    additions[ROOT+'AureaCraft/provenance.json']=(json.dumps(provenance,indent=2).encode()+b'\n',0o644)
    output.parent.mkdir(parents=True,exist_ok=True)
    fd,temp=tempfile.mkstemp(prefix='.aurea-build-',suffix='.ipa',dir=output.parent);os.close(fd)
    original_hashes={};changed=[]
    try:
        with zipfile.ZipFile(original) as source,zipfile.ZipFile(temp,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as dest:
            names=source.namelist()
            if len(names)!=len(set(names)):raise ValueError('Duplicate original entries')
            if any(not safe_archive_name(n) for n in names):raise ValueError('Unsafe original ZIP path')
            if set(names)&set(additions):raise ValueError('New workspace conflicts with original files')
            for item in source.infolist():
                data=source.read(item);original_hashes[item.filename]=sha(data)
                if item.filename==ROOT+'Aurea':
                    data,patch=inject(data);changed.append(item.filename)
                elif item.filename==ROOT+'Info.plist':
                    info=plistlib.loads(data)
                    if info.get('CFBundleIdentifier')!='com.aurea.aurea' or info.get('CFBundleVersion')!='2185':raise ValueError('Unexpected application identity')
                    info.setdefault('NSAppTransportSecurity',{})['NSAllowsLocalNetworking']=True
                    info['AureaStudioIntegration']={'Version':'0.1.0','Mode':'OfflineEffectCraftWorkspace','NativeEffectParity':False}
                    data=plistlib.dumps(info,fmt=plistlib.FMT_BINARY,sort_keys=False);changed.append(item.filename)
                dest.writestr(copy.copy(item),data)
            if len(changed)!=2:raise ValueError('Original executable or metadata missing')
            for name,(data,mode) in sorted(additions.items()):dest.writestr(zip_entry(name,mode),data)
        unchanged=0
        with zipfile.ZipFile(temp) as built:
            if built.testzip() is not None:raise ValueError('Final ZIP CRC check failed')
            for name,h in original_hashes.items():
                if name not in changed:
                    if sha(built.read(name))!=h:raise ValueError('Original resource modified: '+name)
                    unchanged+=1
            for name,(data,mode) in additions.items():
                if built.read(name)!=data:raise ValueError('Added file differs: '+name)
            for name,h in runtime_hashes.items():
                if sha(built.read(name))!=h:raise ValueError('Upstream runtime modified: '+name)
            exe=built.read(ROOT+'Aurea');loads=[c for c in commands(exe) if c.get('name')==DYLIB]
            if len(loads)!=1 or loads[0]['cmd']!=0x80000018:raise ValueError('Extension weak load is missing')
            for name in (ROOT+'Aurea',ROOT+'Frameworks/AureaCraft.dylib'):
                if not (built.getinfo(name).external_attr>>16)&0o111:raise ValueError('Executable permission missing')
            entries=len(built.namelist())
        os.replace(temp,output)
    except BaseException:
        pathlib.Path(temp).unlink(missing_ok=True);raise
    return {'output':output.name,'bytes':output.stat().st_size,'sha256':sha(output.read_bytes()),
      'original_entries':len(original_hashes),'original_entries_unchanged':unchanged,'changed_original_entries':changed,
      'added_entries':len(additions),'total_entries':entries,'unmodified_official_runtime_files':len(runtime_hashes),
      'zip_crc_verified':True,'extension':platform,'patch':patch,'provenance':provenance}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('original','dylib','runtime','integration','upstream','output'):parser.add_argument('--'+name,type=pathlib.Path,required=True)
    parser.add_argument('--report',type=pathlib.Path,required=True);a=parser.parse_args()
    result=package(a.original,a.dylib,a.runtime,a.integration,a.upstream,a.output)
    a.report.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
