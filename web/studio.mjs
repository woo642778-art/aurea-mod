// SPDX-License-Identifier: MIT
// Mobile controls for the unmodified, pinned EffectCraft 0.10.0 engine.
import init, * as ec from './effectcraft_web.js';
import {MAX_FILE,MAX_BUNDLE,safeName,compositionParams,propertyValue,SerialQueue,formatBytes,zipStored,unzipStored} from './core.mjs';
const $=id=>document.getElementById(id);
const state={ready:false,tab:'layers',summary:null,comp:null,tree:null,effects:[],commands:[],playing:false,full:false,busy:0,previewURL:null,lastSaved:null};
const queue=new SerialQueue();
const native=!!window.webkit?.messageHandlers?.aureaStudio;
const bridge=(action,args={})=>native?window.webkit.messageHandlers.aureaStudio.postMessage({action,...args}):Promise.reject(Error('이 기능은 Aurea 앱 내부에서 사용할 수 있습니다.'));
const message=e=>e?.message??String(e);
const exec=(command,params={})=>ec.request('engine.execute',{command,params});
const req=(method,params={})=>ec.request(method,params);
const selected=()=>state.summary?.selectedLayers?.[0];
const uid=()=>crypto.randomUUID().replaceAll('-','').slice(0,12);
function node(tag,text='',attrs={}){const n=document.createElement(tag);if(text!=='')n.textContent=text;for(const[k,v]of Object.entries(attrs)){if(k==='class')n.className=v;else n.setAttribute(k,String(v));}return n;}
function button(label,action,{disabled=false,cls='',title}={}){const b=node('button',label,{type:'button',class:cls});b.disabled=disabled;if(title)b.title=title;b.onclick=()=>Promise.resolve().then(action).catch(showError);return b;}
function row(...children){const r=node('div','',{class:'row'});r.append(...children);return r;}
function hint(text){return node('p',text,{class:'hint'});}
function toast(text){$('toast').querySelector('span').textContent=text;$('toast').hidden=false;}
function showError(error){console.error('Studio:',error);toast(message(error));}
$('toast').querySelector('button').onclick=()=>$('toast').hidden=true;
window.addEventListener('unhandledrejection',e=>{e.preventDefault();showError(e.reason);});
function busy(text){state.busy++;$('busy').textContent=text;$('busy').hidden=false;return()=>{state.busy--;if(!state.busy)$('busy').hidden=true;};}
function mutate(label,task,{refreshAfter=true}={}){
  return queue.run(async()=>{if(!state.ready)throw Error('편집 엔진을 여는 중입니다.');const end=busy(label);try{const result=await task();if(refreshAfter)await refresh();return result;}finally{end();}});
}
function fieldsDialog(title,fields,submitLabel='적용',description=''){
  return new Promise(resolve=>{
    const d=node('dialog'),form=node('form');form.method='dialog';form.append(node('h2',title));if(description)form.append(hint(description));const controls={};
    for(const f of fields){const label=node('label',f.label);let input;
      if(f.options){input=node('select');for(const [value,text]of f.options)input.append(node('option',text,{value}));}
      else if(f.multiline)input=node('textarea','',{rows:f.rows??4});
      else input=node('input','',{type:f.type??'text'});
      input.value=String(f.value??'');input.name=f.name;input.required=!!f.required;if(f.min!==undefined)input.min=f.min;if(f.max!==undefined)input.max=f.max;if(f.step!==undefined)input.step=f.step;
      label.append(input);form.append(label);controls[f.name]=input;
    }
    const footer=node('footer');const cancel=button('취소',()=>d.close());const apply=node('button',submitLabel,{type:'submit',class:'accent'});footer.append(cancel,apply);form.append(footer);d.append(form);document.body.append(d);
    let value=null;form.onsubmit=e=>{e.preventDefault();if(!form.reportValidity())return;value=Object.fromEntries(Object.entries(controls).map(([k,v])=>[k,v.value]));d.close();};
    d.addEventListener('close',()=>{d.remove();resolve(value);},{once:true});d.showModal();
  });
}
async function confirmAction(title,description,label='계속'){return !!await fieldsDialog(title,[],label,description);}
function requireComp(){if(!state.comp)throw Error('컴포지션을 먼저 만드세요.');return state.comp.id;}
function requireLayer(){const id=selected();if(id===undefined)throw Error('레이어를 먼저 선택하세요.');return id;}
function fromBase64(text){const raw=atob(text),out=new Uint8Array(raw.length);for(let i=0;i<raw.length;i++)out[i]=raw.charCodeAt(i);return out;}
async function updatePreview(){
  if(!state.comp)return;
  const frame=await req('render.frame',{comp:state.comp.id,time:state.summary.time,max_side:640,base64:true});
  if(!frame?.png)throw Error('렌더링 엔진이 이미지 데이터를 반환하지 않았습니다.');
  const url=URL.createObjectURL(new Blob([fromBase64(frame.png)],{type:'image/png'}));const previous=state.previewURL;state.previewURL=url;
  $('preview').src=url;$('empty-preview').hidden=true;if(previous)URL.revokeObjectURL(previous);
}
async function refresh({panel=true,preview=true}={}){
  state.summary=await exec('project.summary');state.comp=state.summary.activeComp?await exec('comp.info',{comp:state.summary.activeComp}):null;state.tree=null;
  if(state.comp){$('comp-name').textContent=state.comp.name;$('comp-meta').textContent=`${state.comp.width}×${state.comp.height} · ${state.comp.frameRate} fps`;
    const t=$('time');t.max=Math.max(0,state.comp.duration-1/state.comp.frameRate);t.step=1/state.comp.frameRate;t.value=state.summary.time;
    $('time-label').value=`${Number(state.summary.time).toFixed(3)} s`;
  }else{$('comp-name').textContent='컴포지션 없음';$('comp-meta').textContent='';$('empty-preview').hidden=false;$('preview').removeAttribute('src');}
  $('connection').textContent=`Studio · ${state.summary.dirty?'변경됨':'저장됨'}`;
  if(preview&&state.comp)await updatePreview();if(panel)await renderPanel();
}
async function newComp(){const values=await fieldsDialog('새 컴포지션',[
  {name:'name',label:'이름',value:'새 컴포지션',required:true},{name:'width',label:'너비 (px)',type:'number',value:1280,min:1,max:4096,required:true},
  {name:'height',label:'높이 (px)',type:'number',value:720,min:1,max:4096,required:true},{name:'frameRate',label:'프레임률',type:'number',value:30,min:1,max:120,step:'any',required:true},
  {name:'duration',label:'길이 (초)',type:'number',value:5,min:0.01,max:600,step:'any',required:true}], '만들기','고해상도·긴 영상은 메모리를 많이 사용합니다. 720p의 짧은 작업부터 시작하세요.');
  if(values)await mutate('컴포지션 만드는 중',()=>exec('comp.new',compositionParams(values)));
}
async function addText(){requireComp();const v=await fieldsDialog('텍스트 레이어',[{name:'text',label:'텍스트',value:'Aurea Studio',required:true},{name:'size',label:'글자 크기',type:'number',value:64,min:1,max:1000,required:true}],'추가');if(v)await mutate('텍스트 추가 중',()=>exec('layer.newText',{text:v.text,size:Number(v.size),fill:'#ffffff',position:[state.comp.width/2,state.comp.height/2]}));}
async function addShape(kind){requireComp();await mutate('도형 추가 중',()=>exec('layer.newShape',{kind,name:kind==='ellipse'?'Ellipse':'Rectangle',size:[Math.round(state.comp.width/3),Math.round(state.comp.height/3)],fill:'#a8ccfa',position:[state.comp.width/2,state.comp.height/2]}));}
async function addSolid(){requireComp();const v=await fieldsDialog('단색 레이어',[{name:'name',label:'이름',value:'Solid',required:true},{name:'color',label:'색상',type:'color',value:'#5088c9'}],'추가');if(v)await mutate('단색 레이어 추가 중',()=>exec('layer.newSolid',{name:v.name,color:v.color,width:state.comp.width,height:state.comp.height}));}
function renderLayers(panel){
  panel.append(row(button('파일 가져오기',()=>importFiles()),button('Aurea 선택 미디어',()=>importFiles('selected'),{disabled:!native,title:'효과 적용 전 원본 미디어를 가져옵니다.'})));
  panel.append(row(button('텍스트',addText),button('사각형',()=>addShape('rect')),button('타원',()=>addShape('ellipse')),button('단색',addSolid)));
  panel.append(row(button('실행 취소',()=>mutate('실행 취소',()=>exec('edit.undo'))),button('다시 실행',()=>mutate('다시 실행',()=>exec('edit.redo'))),button('복제',()=>mutate('레이어 복제',()=>exec('edit.duplicate',{layers:[requireLayer()]})),{disabled:selected()===undefined}),button('삭제',async()=>{const id=requireLayer();if(await confirmAction('레이어 삭제','선택 레이어를 삭제합니다. 실행 취소로 되돌릴 수 있습니다.','삭제'))await mutate('레이어 삭제',()=>exec('edit.clear',{layers:[id]}));},{disabled:selected()===undefined})));
  const list=node('div','',{class:'layer-list'});for(const layer of state.comp?.layers??[]){const b=button('',()=>mutate('레이어 선택',()=>exec('layer.select',{layers:[layer.id]})),{cls:`layer-row${state.summary.selectedLayers?.includes(layer.id)?' selected':''}`});b.dataset.layer=layer.id;b.append(node('span',String(layer.index??''),{class:'index'}),node('strong',layer.name),node('small',layer.type));list.append(b);}
  panel.append(list);if(!state.comp?.layers?.length)panel.append(node('p','파일, 텍스트 또는 도형을 추가하세요.',{class:'empty'}));
  panel.append(hint('Aurea와 Studio는 별도의 편집 공간입니다. 가져온 원본에는 Aurea의 효과·키프레임이 포함되지 않습니다. 결과물은 새 미디어 레이어로 되돌릴 수 있습니다.'));
}
function formatValue(v){return typeof v==='string'?v:JSON.stringify(v);}
function propertyEditor(prop,layer,spec){
  const block=node('div','',{class:'property'});block.dataset.property=prop.path;const label=node('label',prop.name??prop.match??prop.path);const value=prop.value;
  let control;
  if(spec?.options){control=node('select');for(const o of spec.options)control.append(node('option',o.label,{value:o.value}));control.value=String(value);}
  else if(typeof value==='boolean'){control=node('select');control.append(node('option','켜짐',{value:'true'}),node('option','꺼짐',{value:'false'}));control.value=String(value);}
  else if(typeof value==='number'){control=node('input','',{type:'number',step:'any'});control.value=value;if(spec?.min!==undefined)control.min=spec.min;if(spec?.max!==undefined)control.max=spec.max;}
  else if(typeof value==='string'){control=node('input','',{type:'text'});control.value=value;}
  else if(Array.isArray(value)&&value.every(v=>typeof v==='number')){control=node('input','',{type:'text'});control.value=JSON.stringify(value);}
  else {block.append(node('strong',prop.name??prop.path),hint('복합 속성입니다. 전체 편집기에서 편집하세요.'));return block;}
  control.setAttribute('aria-label',prop.name??prop.path);label.append(control);block.append(label);
  control.onchange=()=>{let result;try{result=propertyValue(control.value,prop.type,value,spec??{});}catch(e){control.value=formatValue(value);showError(e);return;}
    mutate('속성 적용 중',()=>exec('prop.set',{layer,path:prop.path,value:result,time:state.summary.time,timeBase:'comp'})).catch(showError);};
  const actions=row(button(`키프레임${prop.keys?.length?` (${prop.keys.length})`:''}`,()=>mutate('키프레임 추가',()=>exec('prop.addKey',{layer,path:prop.path,time:state.summary.time,timeBase:'comp'}))),button('표현식',async()=>{
    const old=typeof prop.expression==='string'?prop.expression:(prop.expression?.source??prop.expression?.text??'');
    const v=await fieldsDialog(prop.name??'표현식',[{name:'expression',label:'표현식',value:old,multiline:true}], '적용','빈 값을 적용하면 표현식을 끕니다. 예: wiggle(2, 20)');
    if(v)await mutate('표현식 적용',()=>exec('prop.setExpression',{layer,path:prop.path,expression:v.expression,enabled:!!v.expression.trim()}));}));actions.classList.add('actions');block.append(actions);return block;
}
function propertyGroup(group,layer,depth=0,spec=null){
  if(!group.children)return propertyEditor(group,layer,spec?.params?.find(p=>p.id===group.match||p.id===group.path?.split('/').pop()));
  if(group.effect){const id=typeof group.effect==='string'?group.effect:group.effect.id;spec=state.effects.find(e=>e.id===id)??spec;}
  const d=node('details','',{class:'property-group'});d.open=depth<=1||!!group.effect;d.append(node('summary',group.name||group.match||'속성'));
  for(const child of group.children)d.append(propertyGroup(child,layer,depth+1,spec));return d;
}
async function renderProperties(panel){if(selected()===undefined){panel.append(hint('레이어 탭에서 편집할 레이어를 선택하세요.'));return;}
  const tree=await exec('layer.tree',{layer:selected(),time:state.summary.time,depth:8});state.tree=tree;panel.append(node('h3',tree.name??'속성'));
  if(tree.properties)panel.append(propertyGroup(tree.properties,selected()));else panel.append(hint('속성 트리를 읽지 못했습니다. 전체 편집기를 사용하세요.'));
}
function renderEffects(panel){
  panel.append(hint(`${state.effects.length}개 실제 엔진 이펙트. 레이어를 선택한 후 적용하면 속성 탭에서 값을 바꿀 수 있습니다.`));
  const search=node('input','',{type:'search',placeholder:'이름·카테고리로 검색',class:'search','aria-label':'이펙트 검색'});const list=node('div','',{class:'effect-list'});panel.append(search,list);
  let shown=60;const draw=()=>{list.replaceChildren();const q=search.value.trim().toLowerCase();const found=state.effects.filter(e=>`${e.name} ${e.category} ${e.id}`.toLowerCase().includes(q));
    for(const e of found.slice(0,shown)){const b=button('',async()=>{const layer=requireLayer();await mutate(`${e.name} 적용 중`,async()=>{await exec('effect.apply',{effect:e.id,layers:[layer]});state.tab='properties';});},{cls:'effect-row',disabled:selected()===undefined});b.dataset.effect=e.id;b.append(node('strong',e.name),node('small',`${e.category} · ${e.params?.length??0}개 매개변수`));list.append(b);}
    if(found.length>shown)list.append(button(`${found.length-shown}개 더 보기`,()=>{shown+=60;draw();}));if(!found.length)list.append(hint('검색 결과가 없습니다.'));
  };search.oninput=()=>{shown=60;draw();};draw();
}
async function writeExport(name,bytes,type='application/octet-stream'){
  name=safeName(name);const blob=bytes instanceof Blob?bytes:new Blob([bytes],{type});if(blob.size>MAX_FILE)throw Error('한 파일의 최대 크기는 256 MiB입니다.');if(!blob.size)throw Error('빈 파일은 내보낼 수 없습니다.');
  if(native){const token=location.pathname.split('/').filter(Boolean)[0];const url=new URL(`api/export?name=${encodeURIComponent(name)}`,location.href);
    const response=await fetch(url,{method:'POST',headers:{'Content-Type':type,'X-Aurea-Token':token},body:blob});let result;try{result=await response.json();}catch{throw Error(`저장 응답을 읽지 못했습니다 (${response.status}).`);}if(!response.ok)throw Error(result.error??`저장 실패 (${response.status})`);toast(`${result.name} · 보관함에 저장됨`);return result;
  }
  const url=URL.createObjectURL(blob),a=node('a','',{href:url,download:name});document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);toast(`${name} · 다운로드 요청됨`);return {name,bytes:blob.size,browser:true};
}
async function saveProject({nativeBackup=true,notify=true}={}){
  const result=await ec.saveToBrowser('/Studio-current.ecproj');await ec.flush();state.lastSaved=result;
  if(nativeBackup&&native){const bytes=ec.readFile(result.path);if(!bytes)throw Error('저장한 프로젝트를 다시 읽지 못했습니다.');await writeExport(`Studio-${new Date().toISOString().replaceAll(':','-')}.ecproj`,bytes,'application/json');}
  if(notify)toast(nativeBackup&&native?'프로젝트와 네이티브 보관함 백업을 저장했습니다.':'브라우저 저장소에 프로젝트를 저장했습니다.');return result;
}
async function exportFrame(){requireComp();await mutate('PNG 프레임 렌더링 중',async()=>{const frame=await req('render.frame',{comp:state.comp.id,time:state.summary.time,max_side:0,base64:true});if(!frame?.png)throw Error('PNG 데이터를 만들지 못했습니다.');await writeExport(`${safeName(state.comp.name)}-${Number(state.summary.time).toFixed(3)}.png`,fromBase64(frame.png),'image/png');},{refreshAfter:false});}
async function exportLottie(){requireComp();await mutate('Lottie 내보내는 중',async()=>{const path=`/${uid()}-${safeName(state.comp.name)}.json`;const result=await exec('file.exportLottie',{comp:state.comp.id,path,includeExpressions:true,textAsShapes:true});const data=ec.readFile(path);if(!data)throw Error('Lottie 파일이 생성되지 않았습니다.');await writeExport(path,data,'application/json');if(result?.warnings?.length)toast(`변환 경고: ${JSON.stringify(result.warnings).slice(0,700)}`);},{refreshAfter:false});}
async function exportVideo(){requireComp();const v=await fieldsDialog('영상 렌더링',[
  {name:'format',label:'형식',value:'h264',options:[['h264','H.264 / MP4'],['hevc','HEVC / MP4'],['webm','WebM'],['gif','GIF']]},
  {name:'resolution',label:'해상도',value:'half',options:[['half','1/2 해상도'],['full','원본 해상도'],['quarter','1/4 해상도']]}
], '렌더링 시작','코덱 지원은 기기와 WebKit에 따라 다릅니다. 렌더링이 완료될 때까지 Studio를 닫지 마세요. 오류는 작업 상태에 표시됩니다.');
  if(!v)return;await mutate('렌더 대기열에 추가 중',async()=>{const ext=v.format==='webm'?'webm':v.format==='gif'?'gif':'mp4';await exec('renderQueue.add',{comp:state.comp.id,format:v.format,output:`/${uid()}-${safeName(state.comp.name)}.${ext}`,resolution:v.resolution,timeSpan:'comp',audio:'auto'});await exec('renderQueue.render',{wait:false});state.tab='export';},{refreshAfter:true});
}
async function portableProject(){
  await mutate('휴대용 프로젝트 만드는 중',async()=>{
    const saved=await saveProject({nativeBackup:false,notify:false});const files=ec.files();const manifest={format:'AureaStudio',version:1,project:saved.path,files:[]};const entries=[];let size=0;
    for(const f of files){if(f.path.endsWith('.ecproj')&&f.path!==saved.path)continue;const bytes=ec.readFile(f.path);if(!bytes)continue;size+=bytes.length;if(size>MAX_BUNDLE)throw Error('미디어 포함 96 MiB를 초과했습니다. 개별 프로젝트와 원본 미디어를 따로 보관하세요.');const entry=`files/${String(entries.length).padStart(4,'0')}.bin`;manifest.files.push({path:f.path,entry});entries.push({name:entry,bytes});}
    if(!manifest.files.some(f=>f.path===saved.path))throw Error('현재 프로젝트가 백업에 포함되지 않았습니다.');entries.unshift({name:'manifest.json',bytes:new TextEncoder().encode(JSON.stringify(manifest))});await writeExport(`${safeName(state.comp?.name??'Studio')}.aureastudio.zip`,zipStored(entries),'application/zip');
  },{refreshAfter:false});
}
async function restorePortable(bytes){
  const entries=unzipStored(bytes);const raw=entries.get('manifest.json');if(!raw)throw Error('Aurea Studio 휴대용 프로젝트가 아닙니다.');const manifest=JSON.parse(new TextDecoder().decode(raw));
  if(manifest.format!=='AureaStudio'||manifest.version!==1||!Array.isArray(manifest.files)||manifest.files.length>1023)throw Error('지원하지 않는 휴대용 프로젝트 버전입니다.');
  const paths=new Set(),remap=new Map();for(const f of manifest.files){if(typeof f.path!=='string'||typeof f.entry!=='string'||paths.has(f.path)||!entries.has(f.entry))throw Error('프로젝트의 파일 목록이 손상되었습니다.');paths.add(f.path);remap.set(f.path,`/${uid()}-${safeName(f.path)}`);}
  if(!paths.has(manifest.project))throw Error('프로젝트 데이터가 없습니다.');const project=JSON.parse(new TextDecoder().decode(entries.get(manifest.files.find(f=>f.path===manifest.project).entry)));
  // Rewrite exact media-path string values only; new UUID names cannot collide with existing media.
  const rewrite=value=>{if(typeof value==='string')return remap.get(value)??value;if(Array.isArray(value))return value.map(rewrite);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,rewrite(v)]));return value;};
  const converted=new TextEncoder().encode(JSON.stringify(rewrite(project)));
  for(const f of manifest.files){if(f.path===manifest.project)continue;if(f.path.endsWith('.ecproj'))continue;ec.addFile(remap.get(f.path).slice(1),entries.get(f.entry));}
  await exec('project.summary');ec.addFile(`${uid()}-restored.ecproj`,converted);await exec('project.summary');
}
async function pickBrowserFiles(){return new Promise(resolve=>{const input=$('file-picker');input.value='';input.onchange=()=>resolve([...input.files]);input.oncancel=()=>resolve([]);input.click();});}
async function importFiles(mode='files',existing=null){
  let files=existing;if(!files)files=native?await bridge(mode==='selected'?'selectedMedia':'pickFiles'):await pickBrowserFiles();if(!files?.length)return;if(files.length>8)throw Error('한 번에 최대 8개 파일을 가져올 수 있습니다.');
  const projectFiles=files.filter(f=>/\.(ecproj|aureastudio\.zip)$/i.test(f.name));if(projectFiles.length&&(files.length!==1))throw Error('프로젝트 파일은 한 번에 하나만 여세요.');
  if(projectFiles.length&&!await confirmAction('프로젝트 열기','현재 프로젝트를 먼저 저장한 후 선택한 프로젝트로 전환합니다. .ecproj 단독 파일에는 원본 미디어가 포함되지 않을 수 있습니다.','저장 후 열기'))return;
  await mutate('미디어 가져오는 중',async()=>{
    if(projectFiles.length)await saveProject({nativeBackup:true,notify:false});
    for(const file of files){const size=file.size??file.bytes??0;if(size>MAX_FILE)throw Error(`${file.name}: 256 MiB를 초과했습니다.`);
      let bytes;if(file instanceof File)bytes=new Uint8Array(await file.arrayBuffer());else{const r=await fetch(file.url);if(!r.ok)throw Error(`원본 파일을 읽지 못했습니다 (${r.status}).`);bytes=new Uint8Array(await r.arrayBuffer());}if(bytes.length>MAX_FILE)throw Error('파일이 너무 큽니다.');
      if(/\.aureastudio\.zip$/i.test(file.name)){await restorePortable(bytes);continue;}
      const before=await exec('project.summary');const old=new Set(before.items.map(x=>x.id));ec.addFile(`${uid()}-${safeName(file.name)}`,bytes);const after=await exec('project.summary');
      if(/\.ecproj$/i.test(file.name))continue;
      const added=after.items.filter(x=>!old.has(x.id));if(!added.length)throw Error(`${file.name}: 가져온 프로젝트 항목을 찾지 못했습니다. 지원 형식인지 확인하세요.`);
      for(const item of added){if(item.type==='folder')continue;if(after.activeComp)await exec('layer.addItem',{item:item.id});else if(item.type==='comp'||item.type==='composition')await exec('comp.open',{comp:item.id});}
    }
    await ec.flush();state.tab='layers';
  });
}
async function renderExports(panel){
  panel.append(row(button('현재 프레임 PNG',exportFrame,{disabled:!state.comp}),button('영상 렌더링',exportVideo,{disabled:!state.comp}),button('Lottie JSON',exportLottie,{disabled:!state.comp})));
  panel.append(row(button('휴대용 프로젝트',portableProject),button('프로젝트 파일',()=>mutate('프로젝트 내보내는 중',async()=>{const saved=await saveProject({nativeBackup:false,notify:false});await writeExport('Studio-project.ecproj',ec.readFile(saved.path),'application/json');},{refreshAfter:false}))));
  panel.append(hint('휴대용 프로젝트는 미디어를 포함하며 최대 96 MiB입니다. .ecproj 단독 저장은 원본 미디어를 포함하지 않습니다.'));
  const jobs=await exec('renderQueue.list');const items=Array.isArray(jobs)?jobs:(jobs.items??[]);
  if(items.length){panel.append(node('h3','렌더 대기열'));for(const job of items){const box=node('div','',{class:'job'});box.append(node('strong',job.name??`작업 ${job.id??''}`),node('pre',JSON.stringify(job,null,2),{class:'command-detail'}));panel.append(box);}panel.append(button('작업 상태 새로고침',()=>renderPanel()));}
  panel.append(node('h3','현재 작업공간 파일'));const virtual=ec.files().filter(f=>f.path!==state.lastSaved?.path);
  for(const file of virtual){const line=node('div','',{class:'file-row'});line.append(node('span',`${safeName(file.path)} · ${formatBytes(file.size)}`),button('저장',()=>writeExport(file.path,ec.readFile(file.path))));panel.append(line);}
  if(!virtual.length)panel.append(hint('렌더 결과 또는 가져온 파일이 여기에 표시됩니다.'));
  if(native){panel.append(node('h3','네이티브 보관함'));const files=await bridge('exports');for(const file of files){const line=node('div','',{class:'file-row'});line.append(node('span',`${file.name} · ${formatBytes(file.bytes)}`));const actions=row(button('공유',()=>bridge('shareExport',{id:file.id})));
      if(/\.(png|jpe?g|webp|mp4|mov|m4v|wav|mp3|m4a|aac|aiff)$/i.test(file.name))actions.append(button('Aurea 레이어로',async()=>{if(await confirmAction('Aurea에 추가','현재 열린 Aurea 프로젝트에 새 미디어 레이어를 추가합니다. 기존 레이어는 바꾸지 않습니다.','추가')){const r=await bridge('importExport',{id:file.id});toast(`Aurea 레이어 ${r.layer}로 추가했습니다. Aurea로 돌아가 결과를 확인하세요.`);}}));
      if(/\.(ecproj|aureastudio\.zip)$/i.test(file.name))actions.append(button('열기',async()=>importFiles('files',[await bridge('openSaved',{id:file.id})])));line.append(actions);panel.append(line);}
    if(!files.length)panel.append(hint('저장한 프로젝트와 결과물이 이 기기에 보관됩니다.'));}
}
async function renderMore(panel){
  panel.append(node('h3','컴포지션'));for(const item of state.summary.items.filter(i=>i.type==='comp'||i.type==='composition'))panel.append(button(item.name,()=>mutate('컴포지션 전환',()=>exec('comp.open',{comp:item.id})),{cls:'wide'}));
  panel.append(node('h3','전체 엔진 명령'));panel.append(hint('고급 도구입니다. 실제 명령의 매개변수를 JSON으로 입력합니다. 효과의 일대일 호환이나 모든 코덱 지원을 보장하지 않습니다.'));
  const search=node('input','',{type:'search',placeholder:`${state.commands.length}개 명령 검색`,'aria-label':'명령 검색',class:'search'}),list=node('div');panel.append(search,list);
  const draw=()=>{list.replaceChildren();const q=search.value.toLowerCase();for(const c of state.commands.filter(c=>`${c.id} ${c.label}`.toLowerCase().includes(q)).slice(0,30)){const d=node('details'),sum=node('summary',`${c.label} · ${c.id}`);d.append(sum,node('pre',c.params,{class:'command-detail'}));const input=node('textarea','',{rows:3,'aria-label':`${c.id} 매개변수`});input.value='{}';d.append(input,button('명령 실행',async()=>{let params;try{params=JSON.parse(input.value);}catch{throw Error('매개변수는 JSON 형식으로 입력하세요.');}if(!params||typeof params!=='object'||Array.isArray(params))throw Error('JSON 객체를 입력하세요.');if(!await confirmAction('고급 명령 실행',`${c.id}\n매개변수: ${input.value.slice(0,500)}\n프로젝트를 변경하거나 닫을 수 있습니다. 현재 프로젝트를 저장한 뒤 실행합니다.`,'저장 후 실행'))return;await mutate(c.label,async()=>{await saveProject({nativeBackup:true,notify:false});const result=await exec(c.id,params);toast(JSON.stringify(result)?.slice(0,1000)??'명령이 완료되었습니다.');});}));list.append(d);}};search.oninput=draw;draw();
  panel.append(node('h3','작업공간'));panel.append(row(button('렌더 캐시 비우기',()=>mutate('캐시 비우는 중',()=>exec('edit.purge',{what:'memory'}))),button('상태 확인',async()=>{const info={engine:ec.info(),native:native?await bridge('status'):null};await fieldsDialog('실행 상태',[{name:'status',label:'상태',value:JSON.stringify(info,null,2),multiline:true,rows:12}],'닫기');})));
  panel.append(node('h3','이 빌드에 관하여'));panel.append(hint('Aurea Studio는 공식 EffectCraft 0.10.0 웹 엔진을 오프라인으로 포함한 비공식 확장입니다. Aurea의 네이티브 타임라인과 분리되며 미디어 파일로 연결됩니다. 원본 프로젝트 형식을 서로 완전히 변환하지 않습니다.'));
  panel.append(hint('EffectCraft: ArtCraft team 및 contributors. MIT 또는 Apache-2.0. 모바일 통합 코드: MIT.'));
  for(const name of ['LICENSE-MIT','LICENSE-APACHE','NOTICE','ATTRIBUTION.md'])panel.append(button(name,async()=>{const r=await fetch(name);if(!r.ok)throw Error('라이선스 파일을 읽지 못했습니다.');await fieldsDialog(name,[{name:'license',label:'라이선스',value:await r.text(),multiline:true,rows:14}],'닫기');}));
}
let panelVersion=0;
async function renderPanel(){
  const version=++panelVersion;const target=node('div');for(const b of $('tabs').querySelectorAll('button'))b.setAttribute('aria-pressed',String(b.dataset.tab===state.tab));
  if(state.tab==='layers')renderLayers(target);else if(state.tab==='properties')await renderProperties(target);else if(state.tab==='effects')renderEffects(target);else if(state.tab==='export')await renderExports(target);else await renderMore(target);
  if(version===panelVersion)$('panel').replaceChildren(...target.childNodes);
}
let playbackTimer=null;
async function stopPlayback(){state.playing=false;clearTimeout(playbackTimer);$('play').textContent='재생';if(state.ready)await req('ui.playback',{action:'stop'});}
async function togglePlayback(){if(state.playing){await stopPlayback();await refresh({panel:false});return;}requireComp();state.playing=true;$('play').textContent='정지';await req('ui.playback',{action:'play'});
  const tick=async()=>{if(!state.playing)return;try{await queue.run(()=>refresh({panel:false,preview:!state.full}));}catch(e){await stopPlayback();showError(e);return;}if(state.playing)playbackTimer=setTimeout(tick,180);};playbackTimer=setTimeout(tick,180);
}
for(const b of $('tabs').querySelectorAll('button'))b.onclick=()=>{state.tab=b.dataset.tab;if(state.ready)renderPanel().catch(showError);};
$('new-comp').onclick=()=>newComp().catch(showError);
$('save').onclick=()=>mutate('프로젝트 저장 중',()=>saveProject()).catch(showError);
$('play').onclick=()=>togglePlayback().catch(showError);
$('previous-frame').onclick=()=>mutate('이전 프레임',()=>exec('time.set',{time:Math.max(0,state.summary.time-1/state.comp.frameRate)})).catch(showError);
$('next-frame').onclick=()=>mutate('다음 프레임',()=>exec('time.set',{time:Math.min(state.comp.duration-1/state.comp.frameRate,state.summary.time+1/state.comp.frameRate)})).catch(showError);
$('time').oninput=()=>$('time-label').value=`${Number($('time').value).toFixed(3)} s`;
$('time').onchange=()=>{const time=Number($('time').value);mutate('프레임 이동',async()=>{await stopPlayback();return exec('time.set',{time});}).catch(showError);};
$('mode').onclick=async()=>{if(!state.ready)return;state.full=!state.full;document.body.classList.toggle('full-editor',state.full);$('mode').textContent=state.full?'터치 패널':'전체 편집기';try{if(state.full)await exec('window.workspace',{name:innerWidth<900?'Small Screen':'Default'});else await queue.run(()=>refresh());}catch(e){showError(e);}};
window.effectcraft={request:req,execute:exec,commands:()=>req('engine.commands'),inspect:()=>req('ui.inspect'),renderFrame:p=>req('render.frame',{base64:true,...p}),files:()=>ec.files(),readFile:p=>ec.readFile(p),info:()=>ec.info(),saveToBrowser:p=>ec.saveToBrowser(p),flush:()=>ec.flush(),listStored:()=>ec.listStored()};
window.AureaStudio={
  get ready(){return state.ready;},get counts(){return {effects:state.effects.length,commands:state.commands.length};},
  showLibrary:async()=>{state.tab='export';state.full=false;document.body.classList.remove('full-editor');$('mode').textContent='전체 편집기';if(state.ready)await renderPanel();},
  downloaded:item=>{toast(`${item.name} · 네이티브 보관함 저장 완료`);if(state.tab==='export')renderPanel().catch(showError);},
  flushForClose:async()=>{if(!state.ready)throw Error('편집 엔진의 저장 상태를 확인할 수 없습니다.');await stopPlayback();return queue.run(()=>saveProject({nativeBackup:true,notify:false}));},
  backgroundSave:async()=>{if(state.ready)return queue.run(()=>saveProject({nativeBackup:false,notify:false}));},
  memoryWarning:async()=>{if(!state.ready)return;await stopPlayback();await queue.run(()=>exec('edit.purge',{what:'memory'}));toast('메모리가 부족해 재생을 멈추고 렌더 캐시를 비웠습니다. 작업을 저장하세요.');},
  // Test and integration entry points use the same production command queue.
  command:(id,params={})=>mutate(id,()=>exec(id,params)),refresh:()=>queue.run(()=>refresh()),
  exportFrame,portableProject,importFiles,save:()=>mutate('프로젝트 저장 중',()=>saveProject()),
};
async function boot(){
  const start=performance.now();window.effectcraftLoad={};
  const wasmURL=new URL('effectcraft_web_bg.wasm',location.href);let module;
  try{module=await WebAssembly.compileStreaming(fetch(wasmURL));}catch{const response=await fetch(wasmURL);if(!response.ok)throw Error(`편집 엔진을 읽지 못했습니다 (${response.status}).`);module=await WebAssembly.compile(await response.arrayBuffer());}
  window.effectcraftModule=module;await init({module_or_path:module});window.effectcraftLoad.wasmMs=performance.now()-start;
  $('boot-status').textContent='편집 엔진과 저장된 작업을 복원하고 있습니다.';await ec.start('effectcraft_canvas');
  await exec('prefs.set',{values:{'memory.layerCacheMb':128,'memory.mediaCacheMb':64,'memory.previewCacheMb':64,'memory.reduceCacheWhenLow':true}});
  state.effects=await exec('effect.list');state.commands=await req('engine.commands');
  const info=ec.info();if(!info.restored){await exec('file.newProject');await exec('comp.new',{name:'Studio Composition',width:1280,height:720,frameRate:30,duration:5});}
  state.ready=true;await refresh();$('studio-loading').hidden=true;window.effectcraftLoad.readyMs=performance.now()-start;
  if(info.storage?.backend==='memory')toast('이 환경에서는 영구 저장소를 사용할 수 없습니다. 닫기 전에 휴대용 프로젝트를 내보내세요.');
}
window.AureaStudio.readyPromise=boot().catch(error=>{window.effectcraftLoad.error=message(error);$('boot-status').textContent=`Studio를 열지 못했습니다: ${message(error)}`;$('studio-loading').append(button('다시 시도',()=>location.reload()));throw error;});
