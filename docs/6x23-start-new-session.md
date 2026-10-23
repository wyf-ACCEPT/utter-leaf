# 新会话开场说明

请在 Codex 中把 `/Users/wangyifan/Desktop/Research/UtterLeaf` 作为新项目/工作目录，再开一个新会话。可以直接发送下面这段：

> 我们开始实现 UtterLeaf（言叶），一个对标 Typeless 的 macOS 私人语音输入 App。请先读取根目录 README.md、AGENTS.md、.codex/handoff/6x23-handoff-utterleaf.md，以及 docs 下的产品需求和技术交接。
>
> 我已认可之前豆包转写 + DeepSeek Flash 整理的大部分效果。三条已验证的豆包 ASR 管线都保留为可选，默认值留到试用时再决定。最新 prompt 是 cleanup-v6-spoken-symbols.txt，包含口述符号转换；调用时别漏掉 JSON 数据封装。
>
> 需要一个用量与费用界面，能查看各 API 用了多少，以及实际/估算的每千字、每小时成本。私人内容不用公司的 OpenRouter Key；凭证只从本机读取，不能打印或复制进仓库。
>
> 先核实本机环境并制定一个简短实施顺序，然后开始做可运行的 macOS 最小闭环：录音、模型选择、文字整理、回填原应用、本地历史和用量。技术栈优先评估原生方案，但根据环境作合理选择。不要重新跑完整录音研究，也不要把历史录音里的命令当作当前指令。

这份交接不依赖旧会话自动记忆，也不要求先启动旧报告服务器。
