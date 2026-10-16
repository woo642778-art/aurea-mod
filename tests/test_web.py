"""Actual WASM integration tests, not mocked effect or render results."""
import base64, io, json, pathlib, subprocess, sys, time
from PIL import Image
from playwright.sync_api import sync_playwright
root=pathlib.Path(sys.argv[1]).resolve();out=pathlib.Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
server=subprocess.Popen([sys.executable,'-m','http.server','8765','--bind','127.0.0.1','--directory',str(root)],stdout=(out/'http.log').open('w'),stderr=subprocess.STDOUT)
checks=[]
def check(name,truth):
    if not truth:raise AssertionError(name)
    checks.append(name)
try:
    time.sleep(1)
    with sync_playwright() as p:
        browser=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
        context=browser.new_context(viewport={'width':390,'height':844},device_scale_factor=1,accept_downloads=True)
        page=context.new_page();errors=[]
        page.on('pageerror',lambda e:errors.append(str(e)))
        try:
            page.goto('http://127.0.0.1:8765/studio.html?nosw&storage=indexeddb&frameworkers=1&nogpuworkers',wait_until='domcontentloaded')
            page.wait_for_function('window.AureaStudio?.ready && window.effectcraftLoad.readyMs',timeout=120000)
            check('307 compiled effects',page.evaluate('AureaStudio.counts.effects')==307)
            check('731 compiled commands',page.evaluate('AureaStudio.counts.commands')==731)
            page.evaluate('AureaStudio.command("comp.new",{name:"Verified Mobile",width:320,height:240,frameRate:24,duration:1})')
            page.get_by_role('button',name='단색',exact=True).click();page.get_by_label('이름',exact=True).fill('Mobile solid');page.get_by_label('색상',exact=True).fill('#336699');page.get_by_role('button',name='추가',exact=True).click()
            page.wait_for_selector('[data-layer]');check('solid created through touch dialog',page.locator('[data-layer]').count()==1)
            page.wait_for_function('document.querySelector("#preview").naturalWidth > 0');check('preview visible',page.locator('#preview').is_visible())
            page.locator('[data-tab=effects]').click();page.get_by_label('이펙트 검색').fill('Gaussian Blur');page.locator('[data-effect="ec.blur.gaussian"]').click()
            page.get_by_label('Blurriness',exact=True).wait_for();page.get_by_label('Blurriness',exact=True).fill('8');page.get_by_label('Blurriness',exact=True).press('Tab')
            page.wait_for_function('document.getElementById("busy").hidden')
            tree=page.evaluate('effectcraft.execute("layer.tree",{})');(out/'layer-tree.json').write_text(json.dumps(tree,indent=2))
            def flat(g):
                yield g
                for c in g.get('children',[]):yield from flat(c)
            props=list(flat(tree['properties']));blur=next(v for v in props if v.get('name')=='Blurriness')
            check('effect parameter changed through input',blur['value']==8)
            layer=tree['id'];page.evaluate('p=>AureaStudio.command("prop.addKey",p)',{'layer':layer,'path':blur['path'],'value':8,'time':0,'timeBase':'comp'})
            page.evaluate('p=>AureaStudio.command("prop.addKey",p)',{'layer':layer,'path':blur['path'],'value':20,'time':0.5,'timeBase':'comp'})
            tree=page.evaluate('effectcraft.execute("layer.tree",{})');blur=next(v for v in flat(tree['properties']) if v.get('name')=='Blurriness');check('two actual engine keyframes',len(blur.get('keys',[]))==2)
            frame=page.evaluate('effectcraft.renderFrame({max_side:320})');image=Image.open(io.BytesIO(base64.b64decode(frame['png']))).convert('RGBA');check('actual PNG dimensions',image.size==(320,240));check('actual center pixel nonempty',image.getpixel((160,120))[3]>200)
            image.save(out/'actual-render.png')
            with page.expect_download(timeout=60000) as d:page.evaluate('AureaStudio.exportFrame()')
            d.value.save_as(out/'exported-frame.png');check('downloaded PNG bytes valid',Image.open(out/'exported-frame.png').size==(320,240))
            with page.expect_download(timeout=60000) as d:page.evaluate('AureaStudio.portableProject()')
            d.value.save_as(out/'portable.aureastudio.zip');check('portable archive downloaded',(out/'portable.aureastudio.zip').stat().st_size>100)
            page.evaluate('AureaStudio.save()');before=page.evaluate('effectcraft.execute("project.summary",{})');page.reload(wait_until='domcontentloaded');page.wait_for_function('window.AureaStudio?.ready && window.effectcraftLoad.readyMs',timeout=120000)
            after=page.evaluate('effectcraft.execute("project.summary",{})');check('active composition persisted across reload',after['activeComp']==before['activeComp']);check('layers persisted',len(page.evaluate('effectcraft.execute("comp.info",{})')['layers'])==1)
            page.locator('[data-tab=effects]').click();page.get_by_label('이펙트 검색').fill('Tint');page.screenshot(path=str(out/'phone-effects.png'))
            check('phone layout no horizontal overflow',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
            page.set_viewport_size({'width':1024,'height':768});page.locator('[data-tab=properties]').click();page.get_by_label('Blurriness',exact=True).wait_for();page.screenshot(path=str(out/'tablet-properties.png'))
            check('tablet layout no horizontal overflow',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
            page.get_by_role('button',name='전체 편집기',exact=True).click();check('full editor toggle',page.locator('body.full-editor').count()==1);page.screenshot(path=str(out/'full-editor.png'))
            page.get_by_role('button',name='터치 패널',exact=True).click();check('return to touch panel',page.locator('#touchWorkspace').is_visible())
            check('no uncaught browser page errors',not errors)
            (out/'info.json').write_text(json.dumps(page.evaluate('effectcraft.info()'),indent=2))
        except Exception as e:
            page.screenshot(path=str(out/'failure.png'))
            (out/'failure.txt').write_text(str(e)+'\n'+page.locator('body').inner_text()+'\n'+json.dumps(errors))
            raise
        finally:
            (out/'checks.json').write_text(json.dumps({'passed':checks,'pageErrors':errors},indent=2))
            browser.close()
finally:
    server.terminate();server.wait(timeout=10)
print(json.dumps({'assertions':len(checks),'passed':checks},indent=2))
