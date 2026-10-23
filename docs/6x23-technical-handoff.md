# 技术与评测交接

## 已验证的状态（2026-10-23）

`~/.llm.env` 包含 `DOUBAO_API_KEY` 和 `DEEPSEEK_API_KEY`。此前实测读取成功，文件权限已收紧为 600；本文不包含值。用户指定整理模型使用 Flash。新的会话在调用前只核实变量存在，不打印密钥。

豆包语音资源已开通。新版鉴权为 `X-Api-Key`，还需正确的 `X-Api-Resource-Id` 和每次独立 UUID。不是火山方舟普通文字模型的 Key，也不是账号 Cookie。

- 流式 2.0 的两个模式均完成真实长音频测试。
- 文件标准版 2.0 的提交、查询也完成长音频测试。
- 文件标准版通过 `audio.data` base64 直接传音频成功；当前官方文档主要列出 `audio.url`，该字段属于实测证据，不应被描述为稳定的官方承诺。需保留适配器和错误提示。
- 1.0 `volc.bigasr.sauc.duration` 返回 403 requested resource not granted，未完成质量比较。

流式是专用 WebSocket 二进制协议：配置包、音频包、序号、gzip、最终包和返回状态都要正确处理。实验代码可以参考，不可直接当作生产 SDK。尤其是实时模式：加速灌入长录音触发过 45000081 等包超时，按 200ms 音频/200ms 发包重放后成功。这个失败属于协议/发送方式问题，不能据此说模型质量差。

DeepSeek 整理调用 `https://api.deepseek.com/chat/completions`，model=`deepseek-flash`，thinking disabled。只传豆包输出，不把 Typeless 参考稿塞给整理模型。

## 七月样本与结果

- 备份 DB：`/Users/wangyifan/Library/Mobile Documents/com~apple~CloudDocs/Important-Backup/typeless/6e21-6x13-typeless.db`。
- 7 月按 Asia/Shanghai 选取：UTC `[2026-06-30T16:00:00Z, 2026-07-31T16:00:00Z)`。
- 528 条记录，441 条非空 Typeless 最终稿，528 条原始音频 sidecar 均存在。
- 选了 12 条最长的合格样本；每条 409–736 字符，最少 230 个汉字，合计约 20.96 分钟。
- 4 条用于 prompt 开发，8 条用于评测。不是随机总体抽样，不能外推整体准确率。
- 三条管线在 12 条上都完成 ASR 和 DeepSeek Flash 整理。

8 条评测稿与 Typeless 的归一化字符编辑距离：

| 管线 | 原始 ASR | v5 整理后 |
|---|---:|---:|
| 流式 2.0，说完再返回 | 35.86% | 25.51% |
| 流式 2.0，实时 | 36.54% | 26.34% |
| 文件标准版 2.0 | 35.80% | 25.08% |

该距离去掉了标点/空白并统一大小写，只衡量文字接近程度；不是错误率、WER、语义准确率或用户偏好分数。Typeless 不是人工金标准。用户主观反馈：大部分效果接近，普遍比预期好，已经基本满足需求。没有对 Wispr Flow 做同样本盲测，不能写成胜过该产品的结论。

实验耗时：文件模式在已有录音提交后，加整理的中位数约 9.90 秒；说完再返回使用加速上传，全程约 27.76 秒；实时模式按录音速度重放，最后一包后加整理中位数约 2.00 秒。三者起算点和发送节奏不同，不是公平的模型速度排名，也不是生产延迟 SLA。

## Prompt 继承

- 原实验的 `final.txt` 实际对应 v4，不能因文件名误认为最新版。
- v4 在独立合成指令测试中真的回答了录音中的问题。
- v5 加入 JSON 数据封装后，通过数字、嵌入口述指令、未完句 3 项合成检查；同一批长录音上的结果是回归，不是新的独立盲测。
- 最新候选为 v6：`prompts/cleanup-v6-spoken-symbols.txt`。保留前版并加入符号转换，12 个符号正反例通过；原来的 3 项边界例子也复查了。
- v6 尚未重跑全部长录音；不要把 v5 的长样本指标标成 v6 成绩。
- system prompt 以外还有必需的 user 数据封装，见 `prompts/README.md`。仅复制 system prompt 不能复现实验调用。
- `tap on-31` 的连字符转换与 `TapOn` 的专名拼写是两件事；未来可做用户词表，不猜项目名。

## 费用设计依据

以设置中的定价快照为准，旧报价仅作初始参考：截至 2026-10-22 查询，豆包流式 2.0 小时版为 ¥1/小时，文件标准版 2.0 为 ¥0.8/小时，需在接入时复核开通实例和最新官方计费规则。DeepSeek 文本模型按 token/缓存/时段等计费，不要硬编码成每字固定价。

先前“200 中文字/分钟，USD/CNY=7”的每千字换算只是预算假设，不能用作真实用量账本。真实每千字和每小时应从本地累计金额与真实字符数/音频时长计算。

## 原始资料与可复用代码

完整实验：`/Users/wangyifan/Desktop/Research/Sessions/6x-SpeechToTextBenchmark`。

- `data/manifest.json`：样本 ID、源路径、音频哈希、Typeless 参考稿和 train/test 划分；私人数据，不能提交。
- `results/`：完整请求回执、失败记录、长文本、合成回归及本地报告；私人数据，不能提交。
- `results/metrics.json`：本轮指标来源；新项目中只复制删去逐条数据后的汇总快照。
- `scripts/`：准备样本、三路 ASR、DeepSeek 整理、回归、报告和 loopback server。
- 新项目 `research/benchmark/` 复制了代码、prompt 历史和非私人汇总。为了不重复搬运音频，没有复制 data/results；不要未读说明就直接重跑并产生调用费用。

原对照页地址曾为 `http://127.0.0.1:51542/`，是旧会话的本机临时进程，不保证下一会话还在；应以磁盘资料为准。不要把该地址当 App 服务地址。

## 下一步建议

先核实开发环境，再选择技术栈。SwiftUI + AVAudioEngine/原生全局快捷键/辅助功能输入是建议，不是已锁定方案。优先做垂直闭环和手工试用；保留 ASR 选择、可编辑 prompt、本地用量事件账本，不先做账号系统、云同步或复杂多人功能。

官方参考：

- https://docs.volcengine.com/docs/DoubaoVoice/model-list?lang=zh
- https://docs.volcengine.com/docs/DoubaoVoice/Billinginstructions-21?lang=zh
- https://docs.volcengine.com/docs/DoubaoVoice/task-submission-http-1?lang=zh
- https://api-docs.deepseek.com/guides/thinking_mode/

接手者需要按新会话日期复核这些文档和本机环境。
