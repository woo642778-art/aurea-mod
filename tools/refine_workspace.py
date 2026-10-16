"""Idempotent, auditable corrections found by real-engine integration tests."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'web/studio.mjs';s=p.read_text()
fixes=[
 ('d.open=depth<=1;', 'd.open=depth<=1||!!group.effect;'),
 ("else if(item.type==='composition')", "else if(item.type==='comp'||item.type==='composition')"),
]
for old,new in fixes:
    if old in s:s=s.replace(old,new)
    elif new not in s:raise RuntimeError('Source changed; review rather than applying a blind correction: '+old)
p.write_text(s)
