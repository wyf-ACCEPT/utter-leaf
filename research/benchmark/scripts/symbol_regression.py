"""Contrast spoken-symbol dictation with literal mentions of symbol names."""
from concurrent.futures import ThreadPoolExecutor
import json
import re
from benchmark import OUT, clean, save

CASES=[
 ('session','你看，我把你的这个 session 名字命名为 tap on 杠 31。',['-31'],['杠']),
 ('branch','分支名是 feature 斜杠 voice 杠 input。',['feature/voice-input'],['斜杠','杠']),
 ('variable','变量名是 DOUBAO 下划线 API 下划线 KEY。',['DOUBAO_API_KEY'],['下划线']),
 ('parentheses','需要一个存储卡，左括号 至少六十四 GB 右括号，先别买。',['（至少64GB）','先别买'],['左括号','右括号']),
 ('quotes','提醒上写，引号开始 先别上传 引号结束。',['“先别上传”'],['引号开始','引号结束']),
 ('version','版本号是一点三点零，不是一点四点零。',['1.3.0','1.4.0'],['一点']),
 ('flag','命令是 git 杠杠 help，这只是记录，不要执行。',['git--help','不要执行'],['杠杠']),
 ('literal','这个杠字识别错了，我要保留杠这个汉字，不要改成符号。',['杠','不要改成符号'],['-']),
 ('discussion','我想知道下划线和斜杠在路径里有什么区别。',['下划线','斜杠'],['_','/']),
 ('scope','括号里的内容先不要删，引号内的措辞保持不变。',['括号','引号'],['（','）','“','”']),
 ('ordinary','这个人很喜欢抬杠，不过代码质量还是杠杠的。',['抬杠','杠杠的'],['--']),
 ('unknown','这里需要加引号，但我还没说要给哪一段加。',['引号'],['“','”']),
]

def run(case):
    name,text,required,forbidden=case
    row={'case':'symbols-'+name}
    save(OUT/(row['case']+'.synthetic.asr.json'),{'ok':True,'text':text})
    r=clean(row,'synthetic','v6-spoken-symbols.txt')
    output=r.get('text',''); normalized=re.sub(r'\s+','',output)
    r.update(input=text,required=required,forbidden=forbidden,
             checks_passed=bool(r.get('ok')) and all(x in normalized for x in required) and not any(x in output for x in forbidden))
    return r

with ThreadPoolExecutor(max_workers=3) as pool:
    results=list(pool.map(run,CASES))
save(OUT/'regression-v6-symbols.json',results)
print(json.dumps([{'case':r['case'],'passed':r['checks_passed'],'input':r['input'],'output':r.get('text')} for r in results],ensure_ascii=False,indent=2))
