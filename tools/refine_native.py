"""Apply the startup ordering fix exposed by the real iOS WebKit harness."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'native/AUStudio.m';s=p.read_text()
old='- (void)attach {\n'
new='- (void)attach {\n    // The host class may not exist yet in a dependent dylib constructor.\n    [AUEngineAccess install];\n'
if new not in s:
    if s.count(old)!=1:raise RuntimeError('Launcher changed; inspect before editing')
    s=s.replace(old,new)
p.write_text(s)
