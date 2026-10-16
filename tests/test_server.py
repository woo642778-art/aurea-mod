"""Exercise the same compiled Foundation HTTP server shipped in the iOS extension."""
import json, pathlib, subprocess, sys, tempfile, urllib.request, urllib.error
binary=sys.argv[1]
checks=0
with tempfile.TemporaryDirectory() as temp:
    root=pathlib.Path(temp)/'web';root.mkdir();store=pathlib.Path(temp)/'exports'
    data=bytes(range(256))*20;(root/'fixture.wasm').write_bytes(data)
    (root/'outside-link').symlink_to('/etc/passwd')
    proc=subprocess.Popen([binary,str(root),str(store)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        base=proc.stdout.readline().strip();assert base.startswith('http://127.0.0.1:')
        token=base.rstrip('/').rsplit('/',1)[1]
        def request(path,headers=None,body=None):
            try:
                with urllib.request.urlopen(urllib.request.Request(base+path,data=body,headers=headers or {}),timeout=10) as r:return r.status,r.headers,r.read()
            except urllib.error.HTTPError as r:return r.code,r.headers,r.read()
        def check(value):
            global checks
            assert value, f'HTTP server assertion {checks+1} failed'
            checks+=1
        status,headers,body=request('fixture.wasm');check(status==200 and body==data);check(headers['Content-Type']=='application/wasm')
        status,headers,body=request('fixture.wasm',{'Range':'bytes=10-29'});check(status==206 and body==data[10:30]);check(headers['Content-Range']=='bytes 10-29/5120')
        check(request('fixture.wasm',{'Range':'bytes=99999-'})[0]==416)
        check(request('fixture.wasm',{'Range':'bytes=1-3,5-9'})[0]==416)
        check(request('fixture.wasm',{'Origin':'https://malicious.invalid'})[0]==403)
        check(request('%2e%2e/etc/passwd')[0]==400)
        status,headers,body=request('outside-link');check(status==404);check(body!=pathlib.Path('/etc/passwd').read_bytes())
        check(request('missing')[0]==404)
        check(request('api/export?name=test.png',body=b'abc')[0]==403)
        status,headers,body=request('api/export?name=test.png',{'X-Aurea-Token':token},b'abc');item=json.loads(body);check(status==200 and item['bytes']==3);check((store/item['name']).read_bytes()==b'abc')
        check(request('api/export?name=../test.png',{'X-Aurea-Token':token},b'x')[0]==400)
        check(request('api/export?name=code.js',{'X-Aurea-Token':token},b'x')[0]==400)
        status,_,body=request('api/export?name=backup.aureastudio.zip',{'X-Aurea-Token':token},b'zip');check(status==200 and json.loads(body)['name'].endswith('.aureastudio.zip'))
        check(not list(store.glob('.transfer-*')))
        print(f'Native HTTP server: {checks} assertions passed.')
    finally:
        proc.terminate();proc.wait(timeout=10)
