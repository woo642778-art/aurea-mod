"""Real WASM source-media, portable backup and clean-context restore regression."""
import base64, hashlib, io, json, pathlib, subprocess, sys, time, zipfile
from PIL import Image
from playwright.sync_api import sync_playwright
root=pathlib.Path(sys.argv[1]).resolve(); out=pathlib.Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
checks=[]
def check(name,value):
    if not value: raise AssertionError(name)
    checks.append(name)
fixture=io.BytesIO();Image.new('RGBA',(320,240),(231,43,91,255)).save(fixture,format='PNG');source=fixture.getvalue()
server=subprocess.Popen([sys.executable,'-m','http.server','8766','--bind','127.0.0.1','--directory',str(root)],stdout=(out/'http.log').open('w'),stderr=subprocess.STDOUT)
try:
    time.sleep(1)
    with sync_playwright() as p:
        browser=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
        errors=[]
        def launch():
            context=browser.new_context(viewport={'width':390,'height':844},accept_downloads=True)
            page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
            page.goto('http://127.0.0.1:8766/studio.html?nosw&storage=indexeddb&frameworkers=1&nogpuworkers',wait_until='domcontentloaded')
            page.wait_for_function('window.AureaStudio?.ready && window.effectcraftLoad.readyMs',timeout=120000)
            return context,page
        context,page=launch()
        try:
            effects=page.evaluate('effectcraft.execute("effect.list",{})');commands=page.evaluate('effectcraft.commands()')
            (out/'effects.json').write_text(json.dumps(effects,indent=2));(out/'commands.json').write_text(json.dumps(commands,indent=2))
            check('unique compiled effect IDs',len({e['id'] for e in effects})==307)
            check('unique compiled command IDs',len({c['id'] for c in commands})==731)
            page.evaluate('AureaStudio.command("comp.new",{name:"Source roundtrip",width:320,height:240,frameRate:24,duration:1})')
            page.evaluate('async b64=>{const bytes=Uint8Array.from(atob(b64),c=>c.charCodeAt(0));await AureaStudio.importFiles("files",[new File([bytes],"source # 테스트.png",{type:"image/png"})]);}',base64.b64encode(source).decode())
            check('source import creates one real footage layer',len(page.evaluate('effectcraft.execute("comp.info",{})')['layers'])==1)
            frame=page.evaluate('effectcraft.renderFrame({max_side:320})');pixels=Image.open(io.BytesIO(base64.b64decode(frame['png']))).convert('RGBA')
            check('imported source rendered rather than a proxy',pixels.getpixel((160,120))==(231,43,91,255))
            with page.expect_download(timeout=60000) as d:page.evaluate('AureaStudio.portableProject()')
            portable=out/'source.aureastudio.zip';d.value.save_as(portable)
            with zipfile.ZipFile(portable) as z:
                manifest=json.loads(z.read('manifest.json'));check('portable archive includes exact original media bytes',any(z.read(f['entry'])==source for f in manifest['files']))
            context.close();context,page=launch()
            check('fresh context has no previous media',not page.evaluate('effectcraft.execute("comp.info",{})')['layers'])
            with page.expect_file_chooser() as fc:page.get_by_role('button',name='파일 가져오기',exact=True).click()
            fc.value.set_files(str(portable));page.get_by_role('button',name='저장 후 열기',exact=True).click()
            page.wait_for_function('document.getElementById("busy").hidden && document.getElementById("comp-name").textContent==="Source roundtrip"',timeout=60000)
            check('portable restore creates original composition',page.evaluate('effectcraft.execute("comp.info",{})')['name']=='Source roundtrip')
            check('portable restore creates source layer',len(page.evaluate('effectcraft.execute("comp.info",{})')['layers'])==1)
            restored=page.evaluate('effectcraft.renderFrame({max_side:320})');restored_pixels=Image.open(io.BytesIO(base64.b64decode(restored['png']))).convert('RGBA')
            check('restored media renders identical pixels',restored_pixels.tobytes()==pixels.tobytes())
            page.evaluate('AureaStudio.save()');page.reload(wait_until='domcontentloaded');page.wait_for_function('window.AureaStudio?.ready && window.effectcraftLoad.readyMs',timeout=120000)
            saved=page.evaluate('effectcraft.renderFrame({max_side:320})');saved_pixels=Image.open(io.BytesIO(base64.b64decode(saved['png']))).convert('RGBA')
            check('media survives persistent storage reload',saved_pixels.tobytes()==pixels.tobytes())
            check('no uncaught page errors',not errors);page.screenshot(path=str(out/'restored-source.png'))
        except Exception as e:
            (out/'failure.txt').write_text(str(e)+'\n'+page.locator('body').inner_text());page.screenshot(path=str(out/'failure.png'));raise
        finally:
            (out/'checks.json').write_text(json.dumps({'passed':checks,'pageErrors':errors},indent=2));browser.close()
finally:
    server.terminate();server.wait(timeout=10)
print(json.dumps({'assertions':len(checks),'passed':checks},indent=2))
