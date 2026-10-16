import test from 'node:test';
import assert from 'node:assert/strict';
let c;
try { c=await import('../web/core.mjs'); } catch {}
test('composition validation uses the actual frameRate argument',()=>{
  assert.ok(c,'Mobile core not implemented');
  assert.deepEqual(c.compositionParams({name:' A ',width:'720',height:'1280',frameRate:'30',duration:'5'}),{name:'A',width:720,height:1280,frameRate:30,duration:5});
  for(const patch of [{width:0},{height:9000},{frameRate:'nan'},{duration:0},{name:' '}]) assert.throws(()=>c.compositionParams({name:'A',width:720,height:1280,frameRate:30,duration:5,...patch}));
});
test('finite property values, vector shape and enum membership are checked',()=>{
  assert.ok(c,'Mobile core not implemented');
  assert.equal(c.propertyValue('42','scalar',1,{min:0,max:100}),42);
  assert.throws(()=>c.propertyValue('Infinity','scalar',1,{}));
  assert.throws(()=>c.propertyValue('-1','scalar',1,{min:0}));
  assert.deepEqual(c.propertyValue('[1,2,3]','vec3',[0,0,0],{}),[1,2,3]);
  assert.throws(()=>c.propertyValue('[1,2]','vec3',[0,0,0],{}));
  assert.throws(()=>c.propertyValue('9','enum',0,{options:[{value:0},{value:1}]}));
  assert.equal(c.propertyValue('true','bool',false,{}),true);
  assert.equal(c.propertyValue('literal text','string','',{}),'literal text');
});
test('portable archive round trip and corruption detection',async()=>{
  assert.ok(c,'Portable archive not implemented');
  assert.equal(c.crc32(new TextEncoder().encode('123456789')),0xcbf43926);
  const data=new Uint8Array([0,1,2,255]);
  const blob=c.zipStored([{name:'manifest.json',bytes:new TextEncoder().encode('{"version":1}')},{name:'files/0000.bin',bytes:data}]);
  const raw=new Uint8Array(await blob.arrayBuffer());
  const restored=c.unzipStored(raw);
  assert.deepEqual(restored.get('files/0000.bin'),data);
  const bad=raw.slice();bad[45]^=1;
  assert.throws(()=>c.unzipStored(bad));
  assert.throws(()=>c.zipStored([{name:'../a',bytes:data}]));
  assert.throws(()=>c.zipStored([{name:'a',bytes:data},{name:'a',bytes:data}]));
  assert.throws(()=>c.unzipStored(raw.slice(0,-1)));
});
test('filenames cannot escape native storage and retain extensions',()=>{
  assert.ok(c,'Filename validation not implemented');
  assert.equal(c.safeName('../folder/evil.png'),'evil.png');
  assert.equal(c.safeName(''),'Studio-export');
  assert.ok(c.safeName('x'.repeat(200)+'.mp4').length<=140);
  assert.ok(c.safeName('x'.repeat(200)+'.mp4').endsWith('.mp4'));
  assert.ok(!/[\r\n\\/]/.test(c.safeName('a\r\nb\\c.png')));
});
test('command serialization continues after a failed command without retrying it',async()=>{
  assert.ok(c,'Command serialization not implemented');
  const queue=new c.SerialQueue(),seen=[];
  const a=queue.run(async()=>{seen.push(1);throw Error('expected');});
  const b=queue.run(async()=>{seen.push(2);return 7;});
  await assert.rejects(a);assert.equal(await b,7);assert.deepEqual(seen,[1,2]);
});
