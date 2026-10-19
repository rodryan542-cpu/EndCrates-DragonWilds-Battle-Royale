"""Measure the Lua scheduler with simulated peers, not the game server."""
from pathlib import Path
import json
import statistics
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from support import runtime, MATCH_MOCKS

lua=runtime();lua.execute(MATCH_MOCKS)
lua.execute('config.max_active_matches=50;for i=5,50 do add_zone(i) end;activate(1000)')
tick=lua.eval('function(n)engine:tick(clock+n)end')
samples=[]
for n in range(1,201):
    before=time.perf_counter_ns();tick(n);samples.append((time.perf_counter_ns()-before)/1_000_000)
samples.sort()
result={
    'scope':'Lua scheduler only; mocked peers; no game, terrain, AI, replication, or physics',
    'matches':50,'players':1000,'samples':len(samples),
    'median_ms':round(statistics.median(samples),3),
    'p95_ms':round(samples[int(len(samples)*0.95)-1],3),
    'max_ms':round(max(samples),3),
}
if '--output' in sys.argv:
    output=Path(sys.argv[sys.argv.index('--output')+1])
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2))
