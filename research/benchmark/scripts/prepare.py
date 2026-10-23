"""Prepare a reproducible, private July dictation evaluation set."""
import hashlib
import json
from pathlib import Path
import random
import re
import shutil
import sqlite3
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data'
DATA.chmod(0o700)
DB = Path('/Users/wangyifan/Library/Mobile Documents/com~apple~CloudDocs/Important-Backup/typeless/6e21-6x13-typeless.db')
db = sqlite3.connect('file:' + str(DB) + '?mode=ro', uri=True)
fields = ['id', 'created_at', 'duration', 'typeless', 'source_audio']
rows = [dict(zip(fields, row)) for row in db.execute("SELECT id,created_at,duration,refined_text,audio_local_path FROM history_v2 WHERE created_at >= '2026-06-30T16:00:00' AND created_at < '2026-07-31T16:00:00' ORDER BY created_at")]
texts = [r for r in rows if r['typeless']]
eligible = [r for r in texts if 200 < len(r['typeless']) and 15 <= r['duration'] <= 180
            and not re.search(r'\d{9,}|sk-[A-Za-z0-9]|密码|身份证|私钥|助记词', r['typeless'])]
longest = sorted(eligible, key=lambda r:len(r['typeless']), reverse=True)[:12]
assert len(longest) == 12
rng = random.Random(20260723)
train = rng.sample(longest, 4)
selected = [r for r in longest if r not in train]
manifest = []
for split, collection in [('train', train), ('test', selected)]:
    for i, row in enumerate(collection, 1):
        case = f'{split}-{i:02d}'
        folder = DATA / case
        folder.mkdir(exist_ok=True, mode=0o700)
        src = Path(row['source_audio'])
        assert src.is_file()
        shutil.copy2(src, folder / 'audio.ogg')
        subprocess.run(['/opt/homebrew/bin/ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', str(src), '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', str(folder / 'audio.wav')], check=True, timeout=30)
        entry = {**row, 'case':case, 'split':split, 'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
                 'ogg':str(folder / 'audio.ogg'), 'wav':str(folder / 'audio.wav')}
        manifest.append(entry)
        for file in folder.iterdir(): file.chmod(0o600)
stats = {'month_timezone':'Asia/Shanghai', 'start_utc':'2026-06-30T16:00:00Z', 'end_utc':'2026-07-31T16:00:00Z',
         'records':len(rows), 'audio_available':sum(Path(r['source_audio']).is_file() for r in rows),
         'nonempty_text':len(texts), 'paragraphs':sum('\n\n' in r['typeless'] for r in texts),
         'numbered_lists':sum(bool(re.search(r'(?m)^\d+[.、]',r['typeless'])) for r in texts),
         'latin_text':sum(bool(re.search('[A-Za-z]',r['typeless'])) for r in texts),
         'total_audio_seconds':sum(r['duration'] or 0 for r in rows), 'seed':20260723,
         'train_cases':4, 'test_cases':8, 'reference_policy':'Typeless is a comparison output, not ground truth',
         'selection':'Twelve longest eligible July outputs, all over 200 characters; seeded 4/8 split; not a population accuracy estimate'}
(DATA / 'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
(DATA / 'inventory.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2))
print(json.dumps(stats,ensure_ascii=False))
for r in manifest: print(json.dumps({k:r[k] for k in ['case','created_at','duration','typeless']},ensure_ascii=False))
