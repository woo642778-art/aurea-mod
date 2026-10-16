// SPDX-License-Identifier: MIT
export const MAX_FILE=256*1024*1024;
export const MAX_BUNDLE=96*1024*1024;
export function safeName(input,fallback='Studio-export') {
  let name=String(input??'').split(/[\\/]/).pop().replace(/[\x00-\x1f\x7f]/g,'').replace(/^\.+/,'').trim();
  if(!name) return fallback;
  const dot=name.lastIndexOf('.'),ext=dot>0?name.slice(dot).slice(0,20):'';
  return name.length>140?name.slice(0,140-ext.length)+ext:name;
}
function number(value,label,min,max) {
  if(value===null || value===undefined || String(value).trim()==='')throw Error(`${label}: 값을 입력하세요.`);
  const n=Number(value);
  if(!Number.isFinite(n) || n<min || n>max)throw Error(`${label}: ${min}–${max} 범위의 숫자를 입력하세요.`);
  return n;
}
export function compositionParams(values) {
  const name=String(values.name??'').trim();
  if(!name || name.length>120)throw Error('컴포지션 이름은 1–120자로 입력하세요.');
  const width=number(values.width,'너비',1,4096),height=number(values.height,'높이',1,4096);
  if(!Number.isInteger(width)||!Number.isInteger(height)||width*height>16777216)throw Error('해상도는 정수로, 최대 4096×4096까지 입력하세요.');
  return {name,width,height,frameRate:number(values.frameRate,'프레임률',1,120),duration:number(values.duration,'길이(초)',0.01,600)};
}
export function propertyValue(text,type,current,spec={}) {
  if(type==='string' || typeof current==='string')return String(text);
  if(type==='bool' || typeof current==='boolean') {
    if(text===true||text==='true')return true;
    if(text===false||text==='false')return false;
    throw Error('참 또는 거짓 값이 필요합니다.');
  }
  if(typeof current==='number' || ['scalar','enum','int','integer','angle','layer'].includes(type)) {
    const n=number(text,spec.name??'값',spec.min??-1e12,spec.max??1e12);
    if(spec.options && !spec.options.some(o=>o.value===n))throw Error('목록에 있는 옵션을 선택하세요.');
    if(['int','integer','layer'].includes(type) && !Number.isInteger(n))throw Error('정수를 입력하세요.');
    return n;
  }
  let value;
  try{value=JSON.parse(String(text));}catch{throw Error('올바른 JSON 값을 입력하세요.');}
  if(Array.isArray(current)) {
    if(!Array.isArray(value)||value.length!==current.length||!value.every(v=>typeof v==='number'&&Number.isFinite(v)))throw Error(`${current.length}개의 유한한 숫자가 필요합니다.`);
    if((type==='color'||spec.type==='color') && !value.every(v=>v>=0&&v<=1))throw Error('색상 채널은 0–1 범위입니다.');
  } else if(current && typeof current==='object') {
    if(!value||typeof value!=='object'||Array.isArray(value))throw Error('JSON 객체가 필요합니다.');
  }
  return value;
}
export class SerialQueue {
  #tail=Promise.resolve();
  run(task) { const result=this.#tail.then(task);this.#tail=result.catch(()=>{});return result; }
  idle(){return this.#tail;}
}
export function formatBytes(bytes){return bytes>=1048576?`${(bytes/1048576).toFixed(1)} MiB`:`${(bytes/1024).toFixed(1)} KiB`;}
const CRC_TABLE=new Uint32Array(256);
for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?0xedb88320^(c>>>1):c>>>1;CRC_TABLE[n]=c>>>0;}
export function crc32(bytes){let c=0xffffffff;for(let i=0;i<bytes.length;i++)c=CRC_TABLE[(c^bytes[i])&255]^(c>>>8);return (c^0xffffffff)>>>0;}
function archiveName(name){return typeof name==='string' && name.length>0 && name.length<=240 && !/[\\\x00-\x1f\x7f]/.test(name) && name.split('/').every(p=>p && p!=='.' && p!=='..');}
function bytesView(size){const bytes=new Uint8Array(size);return {bytes,view:new DataView(bytes.buffer)};}
export function zipStored(entries) {
  if(!Array.isArray(entries)||entries.length<1||entries.length>1024)throw Error('아카이브 항목 수가 올바르지 않습니다.');
  const parts=[],central=[],names=new Set();let offset=0,total=0;
  for(const entry of entries){
    if(!archiveName(entry.name)||names.has(entry.name)||!(entry.bytes instanceof Uint8Array))throw Error('잘못되었거나 중복된 아카이브 경로입니다.');
    names.add(entry.name);total+=entry.bytes.length;if(total>MAX_BUNDLE)throw Error('휴대용 프로젝트는 미디어 포함 96 MiB까지 지원합니다.');
    const name=new TextEncoder().encode(entry.name),crc=crc32(entry.bytes),size=entry.bytes.length;
    const l=bytesView(30+name.length),v=l.view;
    v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint16(6,0x800,true);v.setUint32(14,crc,true);v.setUint32(18,size,true);v.setUint32(22,size,true);v.setUint16(26,name.length,true);l.bytes.set(name,30);
    parts.push(l.bytes,entry.bytes);
    const h=bytesView(46+name.length),d=h.view;
    d.setUint32(0,0x02014b50,true);d.setUint16(4,20,true);d.setUint16(6,20,true);d.setUint16(8,0x800,true);d.setUint32(16,crc,true);d.setUint32(20,size,true);d.setUint32(24,size,true);d.setUint16(28,name.length,true);d.setUint32(42,offset,true);h.bytes.set(name,46);central.push(h.bytes);offset+=l.bytes.length+size;
  }
  const centralSize=central.reduce((n,a)=>n+a.length,0),e=bytesView(22),v=e.view;
  v.setUint32(0,0x06054b50,true);v.setUint16(8,entries.length,true);v.setUint16(10,entries.length,true);v.setUint32(12,centralSize,true);v.setUint32(16,offset,true);
  return new Blob([...parts,...central,e.bytes],{type:'application/zip'});
}
export function unzipStored(input) {
  const a=input instanceof Uint8Array?input:new Uint8Array(input),view=new DataView(a.buffer,a.byteOffset,a.byteLength);
  const bad=()=>{throw Error('유효한 Studio 휴대용 프로젝트가 아닙니다. 손상·압축·중복 경로를 확인하세요.');};
  if(a.length<22||a.length>MAX_BUNDLE+1024*1024)bad();
  const end=a.length-22;
  if(view.getUint32(end,true)!==0x06054b50 || view.getUint16(end+20,true)!==0 || view.getUint16(end+4,true)!==0 || view.getUint16(end+6,true)!==0)bad();
  const count=view.getUint16(end+10,true),centralSize=view.getUint32(end+12,true),centralStart=view.getUint32(end+16,true);
  if(count<1||count>1024||view.getUint16(end+8,true)!==count||centralStart+centralSize!==end)bad();
  let position=centralStart,local=0,total=0;const files=new Map(),decoder=new TextDecoder('utf-8',{fatal:true});
  for(let i=0;i<count;i++){
    if(position+46>end||view.getUint32(position,true)!==0x02014b50)bad();
    const flags=view.getUint16(position+8,true),method=view.getUint16(position+10,true),crc=view.getUint32(position+16,true),size=view.getUint32(position+20,true),raw=view.getUint32(position+24,true),nameLen=view.getUint16(position+28,true),extra=view.getUint16(position+30,true),comment=view.getUint16(position+32,true),off=view.getUint32(position+42,true);
    if((flags!==0 && flags!==0x800)||method!==0||size!==raw||off!==local||position+46+nameLen+extra+comment>end)bad();
    let name;try{name=decoder.decode(a.subarray(position+46,position+46+nameLen));}catch{bad();}
    if(!archiveName(name)||files.has(name)||local+30>centralStart||view.getUint32(local,true)!==0x04034b50)bad();
    const ln=view.getUint16(local+26,true),le=view.getUint16(local+28,true),dataStart=local+30+ln+le;
    if(view.getUint16(local+6,true)!==flags||view.getUint16(local+8,true)!==0||view.getUint32(local+14,true)!==crc||view.getUint32(local+18,true)!==size||view.getUint32(local+22,true)!==raw||dataStart+size>centralStart)bad();
    let localName;try{localName=decoder.decode(a.subarray(local+30,local+30+ln));}catch{bad();}if(localName!==name)bad();
    total+=size;if(total>MAX_BUNDLE)bad();const data=a.slice(dataStart,dataStart+size);if(crc32(data)!==crc)bad();files.set(name,data);
    local=dataStart+size;position+=46+nameLen+extra+comment;
  }
  if(position!==end||local!==centralStart)bad();return files;
}
