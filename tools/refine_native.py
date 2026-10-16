"""Keep one main-thread startup retry; exercise the mock after UI activation.

AureaEngine observation is event-driven. A mock that never renders again after
scene construction does not model an actively edited Aurea project.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'native/AUStudio.m';s=p.read_text()
redundant='- (void)attach {\n    // The host class may not exist yet in a dependent dylib constructor.\n    [AUEngineAccess install];\n'
s=s.replace(redundant,'- (void)attach {\n')
expected='if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self attach];});return;}\n    [AUEngineAccess install];'
if expected not in s:raise RuntimeError('Main-thread engine observation retry is missing')
p.write_text(s)
p=root/'tests/ios_smoke.m';s=p.read_text()
old='UIButton *launcher=[self.window viewWithTag:0x41554352];\n'
new=old+'    // Model a render request from the active host editor after scene activation.\n    if(launcher){[self.engine requestRender];}\n'
if new not in s:
    if s.count(old)!=1:raise RuntimeError('Mock host lifecycle changed')
    s=s.replace(old,new)
s=s.replace("check('reply handler and mock engine captured',status.available===true)","check('reply handler and mock engine captured '+JSON.stringify(status),status.available===true)")
p.write_text(s)
