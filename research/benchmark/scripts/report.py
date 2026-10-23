"""Generate a local-only evaluation document and reproducible metrics."""
from collections import Counter
from datetime import datetime
import hashlib
import html
import json
from pathlib import Path
import random
import re
import statistics
import unicodedata

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'results'
MANIFEST=json.loads((ROOT/'data/manifest.json').read_text())
TEST=[x for x in MANIFEST if x['split']=='test']
REVIEW=random.Random(20261023).sample(TEST,3)


def load(name):
    p=OUT/name
    return json.loads(p.read_text()) if p.exists() else {}


def normalize(s):
    return ''.join(c for c in unicodedata.normalize('NFKC',s).casefold() if c.isalnum())


def distance(a,b):
    previous=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        current=[i]
        for j,y in enumerate(b,1): current.append(min(current[-1]+1,previous[j]+1,previous[j-1]+(x!=y)))
        previous=current
    return previous[-1]


def main():
    detail=[]
    metrics={}
    columns=[('raw-final','v2-final.asr.json'),('baseline','v2-final.v1-baseline.clean.json'),
             ('v4-final','v2-final.final.clean.json'),('v5-final','v2-final.v5-final.clean.json'),
             ('raw-realtime','v2-realtime.asr.json'),('v5-realtime','v2-realtime.v5-final.clean.json'),
             ('raw-file','v2-file.asr.json'),('v5-file','v2-file.v5-final.clean.json')]
    for label,suffix in columns:
        edits=total=0; times=[]; clean_times=[]; ratios=[]; paragraphs=[]; success=0
        for row in TEST:
            receipt=load(row['case']+'.'+suffix)
            if not receipt.get('ok'): continue
            success+=1
            text=receipt.get('text','')
            a,b=normalize(text),normalize(row['typeless'])
            d=distance(a,b);edits+=d;total+=len(b)
            times.append(receipt['elapsed_ms']/1000)
            ratios.append(len(text)/len(row['typeless']))
            paragraphs.append(len([x for x in text.split('\n\n') if x.strip()]))
            detail.append({'case':row['case'],'stage':label,'normalized_reference_distance':d/len(b),
                           'chars':len(text),'reference_chars':len(row['typeless']),'paragraphs':paragraphs[-1]})
        metrics[label]={'successful':success,'total':len(TEST),'weighted_reference_edit_distance':edits/total if total else None,
                        'median_elapsed_seconds':statistics.median(times) if times else None,
                        'mean_length_ratio_to_typeless':statistics.mean(ratios) if ratios else None,
                        'mean_paragraphs':statistics.mean(paragraphs) if paragraphs else None}
    timings={}
    for variant in ['v2-final','v2-realtime','v2-file']:
        pairs=[]
        for row in TEST:
            a=load(row['case']+'.'+variant+'.asr.json')
            b=load(row['case']+'.'+variant+'.v5-final.clean.json')
            if a.get('ok') and b.get('ok'):
                pairs.append({'case':row['case'],'audio_seconds':a['audio_seconds'],'asr_seconds':a['elapsed_ms']/1000,
                              'cleanup_seconds':b['elapsed_ms']/1000,'pipeline_seconds':(a['elapsed_ms']+b['elapsed_ms'])/1000,
                              'asr_tail_seconds':a['tail_ms']/1000})
        timings[variant]=pairs
    inventory=json.loads((ROOT/'data/inventory.json').read_text())
    summary={'inventory':inventory,'metrics':metrics,'timings':timings,
             'review_cases':[x['case'] for x in REVIEW], 'review_seed':20261023,
             'important':'Reference edit distance is NOT ASR WER, accuracy, or semantic quality. Typeless is not ground truth.',
             'prompt_development':'v1-v4 used four training cases; v4 frozen before held-out cleanup. v5 changed input framing after a separate synthetic instruction-injection failure. v5 outputs on the same eight test cases are a regression comparison, not a fresh blind test.',
             'file_model_limitation':'File-standard-2.0 was tested using audio.data base64 after successful public-sample submission and query. This input field is observed working but not listed in the current URL-oriented official schema. No public audio hosting was used.',
             'v1_model_limitation':'1.0 resource rejected 403. Two streaming variants are modes of the streaming 2.0 model; the third is file-standard 2.0.',
             'latency_limitation':'Final mode used accelerated recorded-file upload; realtime used 200ms replay pacing. Wall times cannot be compared as model speed benchmarks.',
             'prompt_sha256':hashlib.sha256((ROOT/'prompts/v5-final.txt').read_bytes()).hexdigest()}
    (OUT/'metrics.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    (OUT/'per-case-metrics.json').write_text(json.dumps(detail,ensure_ascii=False,indent=2))
    sections=[]
    for row in REVIEW+[x for x in TEST if x not in REVIEW]:
        blocks=[]
        entries=[('Typeless 最终文字',row['typeless'])]
        for title,suffix in [('豆包 2.0 说完再返回：原始转写','v2-final.asr.json'),
                             ('豆包 2.0 说完再返回 + DeepSeek Flash / v5','v2-final.v5-final.clean.json'),
                             ('豆包 2.0 实时 + DeepSeek Flash / v5','v2-realtime.v5-final.clean.json'),
                             ('豆包文件标准版 2.0 + DeepSeek Flash / v5','v2-file.v5-final.clean.json'),
                             ('简单 prompt v1（相同说完再返回原稿）','v2-final.v1-baseline.clean.json')]:
            entries.append((title,load(row['case']+'.'+suffix).get('text','Unavailable')))
        for title,text in entries:
            blocks.append('<h3>'+html.escape(title)+'</h3><div class="text">'+html.escape(text)+'</div>')
        sections.append('<section><h2>'+row['case']+' · '+row['created_at']+' · '+str(round(row['duration'],1))+' 秒 / Typeless '+str(len(row['typeless']))+' 字</h2><audio controls preload="none" src="/audio/'+row['case']+'"></audio><p>建议听原音后分别判断：信息是否完整；数字、否定和专名是否正确；是否有擅自增加；分段是否自然。</p>' + ''.join(blocks)+'</section>')
    rows=''.join('<tr><td>'+label+'</td><td>'+str(v['successful'])+'/8</td><td>'+f"{v['weighted_reference_edit_distance']:.1%}"+'</td><td>'+f"{v['mean_length_ratio_to_typeless']:.2f}"+'</td><td>'+f"{v['mean_paragraphs']:.1f}"+'</td></tr>' for label,v in metrics.items() if v['successful'])
    prompt=html.escape((ROOT/'prompts/v5-final.txt').read_text())
    header='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>July Typeless / Doubao 对照评测</title><style>
    body{font:16px/1.7 system-ui,sans-serif;max-width:1000px;margin:40px auto;padding:0 24px;color:#222;background:#fafafa}section{margin:48px 0;border-top:2px solid #bbb}h1,h2,h3{line-height:1.4}.text,pre{white-space:pre-wrap;overflow-wrap:anywhere;background:white;border:1px solid #ddd;border-radius:6px;padding:20px}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:8px;text-align:left}audio{width:100%}.note{background:#fff4d6;padding:20px}a{color:#1456a0}</style>'''
    caveat='''<h1>July Typeless / Doubao 对照评测</h1><p>2026-10-23 · 个人本地报告 · 12 条长录音，4 条训练 / 8 条评测，每条 409–736 字。未向公司 OpenRouter 发送音频或正文。</p>
    <div class="note">Typeless 是对照，不是人工金标准；以下编辑距离不是准确率。1.0 未获资源权限。本次私人录音对比流式 2.0 的两种模式与文件标准版 2.0。文件标准版的 audio.data 直传已实测完成，但当前官方文档主要列出 URL 输入，接法可能变动。没有建立私人录音公网链接。v4 是冻结后评测；v5 是边界测试失败后的修订，同一批样本上的回归结果不能当作全新盲测。实时模式按录音速度重放，其他模式提交已录好的文件，耗时不作公平速度排名。</div>
    <p>前 3 条用固定随机种子 20261023 抽取，完整保留；其后是其余 5 条。没有按效果挑选。</p><h2>描述性指标</h2><table><tr><th>管线</th><th>成功</th><th>与 Typeless 的归一化编辑距离</th><th>长度 / Typeless</th><th>平均段落</th></tr>'''
    doc=header+caveat+rows+'</table><details><summary>查看完整 v5 prompt</summary><pre>'+prompt+'</pre></details>'+''.join(sections)+'</html>'
    (OUT/'review.html').write_text(doc)
    print(json.dumps(summary,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
