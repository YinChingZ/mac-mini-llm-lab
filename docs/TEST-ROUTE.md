<!-- Generated from the PDF source (tmp/pdfs/new_route.py); edit the source, not this file. -->
# 测试路线（2026-10-30 修订）

本文件是《七台 Mac mini 本地 LLM 实验指南》测试路线部分的文本版，供 Agent 读取。章号与 PDF `Mac_Mini_LLM_Lab_Guide_RevisedRoute_20261030_ZH_EN.pdf` 一致；基础设施步骤（第03–17章）、故障排查与购买附录只在 PDF 中，未改动。只保留中文，英文对照见 PDF。所有速度与时间均为估算，未测。

命令约定：`python lab.py ...` 在 mini01（已激活 `~/llm-lab/.venv`）执行；`python3 lab.py ...` 在 MacBook 客户端执行；`$API` = `http://<mini01以太网IP>:8080`。

## 02 · 你将走过的路线

*The revised route and stop points*

| 阶段 / Stage | 时间 / When | 完成标志 / Exit check |
|---|---|---|
| P0 只读快照 / Read-only | 现在至11-03 09:00 | 七台T0快照，MAC交学校 / T0 on all seven |
| P1 试点机 / Pilot | 10-30 16:00起 | DM7过T1；安装、冻结、下载；单机探针 / T1, install, probe |
| P2 全集群 / Cluster | 11-03 09:00起 | 六台接线过T2；第04–17章；权重校验 / T2, setup, hashes |
| P3 校准 / Calibrate | 约半天 | 小模型1/2/4台开销 / Pipeline overhead |
| P4 基线 / Baseline | 约1天 | A4功能与引擎基准 / A4 function and bench |
| P5 闸门0 / Gate 0 | 约一晚 | all_sum延迟；决定是否试TP / Decides TP |
| P6 质量 / Quality | 每配置约6–8小时 | A4、E2批处理；BF16只跑必要题 / Batched screens |
| P7 体验与负载 / Load | 数天 | 等待时间、长上下文、并发、D33 |
| P8 稳定与决策 / Decide | 2小时+8小时 | 浸泡测试；选两套配置 / Soak, choose |

时间都是按硬件规格推算的估算，只用于排期，不写进结论。每个阶段都可以暂停：按第43章停止服务、正常关机，再按恢复检查表继续。

Thunderbolt 章节移到附录第54–56章，当前路线不用：基础款 M4 只有 TB4，RDMA 需要 TB5 与 macOS 26.2，不适用；目前也没有买线计划。全部测试走千兆以太网。

> 只想走最少步骤：看单独的《最简实验流程》，它只保留得出结论必须做的部分。

## 18 · 测试路线的总原则

*Principles of the revised route*

第18–42章取代旧版的测试章节；第03–17章的基础设施步骤不变。主线不变：在官方 MLX 上测出 Qwen3.8-27B 的质量、速度、并发与稳定性，选出部署配置，结果可复查。

只写实测数字。下表与后文中的 tok/s 和小时数都是按 120GB/s 带宽推算的估算，只用于排期；结果表里未测的格子留空。

| 配置 / Setup | 估算 / Estimate |
|---|---|
| A4：q8 四机流水线，单请求 | 约3–3.7 tok/s；8192 token 约37–45分钟 |
| R7：bf16 七机流水线，单请求 | 约1.6–1.9 tok/s；8192 token 约72–85分钟 |
| E2：q4 双机流水线，单请求 | 约5–6.5 tok/s；8192 token 约21–27分钟 |
| quality60 一轮（约24万输出token） | 并发1约20小时；批处理4–8约6–8小时 |

四处主要改动：① 质量筛选与延迟测量分开：正确率与批大小基本无关，质量用批处理跑；只有“用户真实等待时间”保持 batch=1。② BF16 只跑必要的题。③ 先用小模型量出以太网流水线开销。④ MacBook 当客户端。

版本继续固定：MLX 0.32.2 与第09章记录的 mlx-lm 提交。上游已有更新（MLX 0.32.4），改动主要是 RDMA 修复，与本路线无关。要测 mxfp8 等新格式时另建版本队列，不在原队列中途升级。

> 不强行调高 GPU 内存上限，先实测默认值（第23章）。研究私有数据和其他项目的数据，不为腾磁盘而删除。

## 19 · 共用期、试点机与机器分工

*Shared-use window, pilot node and roles*

六台与另一个研究项目共用，对方运行到 2026-11-03 09:00。期间这六台只做只读快照：不接线、不重启、不升级、不改主机名、不建账户、不下载大文件、不跑 MLX。备用窗口 11-06 至 11-10 若被占用，规则相同；长测试不要跨进去。

```bash
bash scripts/netprobe.sh snapshot | tee "netprobe-$(hostname -s)-T0.txt"
bash scripts/netprobe.sh egress | tee "netprobe-$(hostname -s)-T1.txt"
```

netprobe.sh 在项目仓库 mac-mini-llm-lab 的 scripts 目录，只读，不改设置、不读钥匙串。七台都跑第一行（T0），输出里的 MAC 地址交学校登记。DM7 在 10-30 16:00 后可自由使用：接交换机前后各跑一次 T0，再跑第二行（T1）。

T1 通过：captive_portal=none；各站点返回任意 HTTP 状态码（不是 000）；20 次 TLS 握手 0 次失败；MTU 1500 通过。不通过就按网络配置方案判断属于 S1–S5 哪种，带着结果找学校。

| PDF代号 / Label | 建议机器 / Machine | 原因 / Why |
|---|---|---|
| mini01 | DM7 | 试点、下载中心、rank 0 / Pilot, hub, rank 0 |
| mini02–05 | 四台大盘机器 / Four roomy disks | A4 全在大盘上 / A4 on roomy disks |
| mini06 | DM5（空闲约33GB） | 可放q4；q8要外置SSD / q4 fits |
| mini07 | node0（空闲约25GB） | 可放q4；q8要外置SSD / q4 fits |
| 客户端 / Client | MacBook | 只发请求 / Sends requests only |

> 不改主机名也可以：在第10章的表里写下“PDF代号 → 实际主机名”，命令里替换即可。机器之间一律用 IP，不依赖 .local。

## 20 · 试点机：预检与单机小模型

*Pilot: preflight and a single-node small model*

mini01（DM7）按第08、09、15、16章安装、冻结版本、下载 small 与 q8。q4 在 9-14 更新过：冻结后打开 model-lock.json，核对 q4 的 revision 与工具包固定的一致；不一致时以锁文件为准，并记下来。

每个模型第一次使用前执行 preflight：严格权重检查配合延迟加载，核对架构、权重是否齐全、PP 索引与模板。它不求值整个模型，也不是容量实测。

```bash
python lab.py preflight small
python lab.py preflight q8
python lab.py fix-index q8   # 仅当索引键不匹配 / only on index mismatch
```

通过：pipeline 与 pipeline_index_matches 为 true；只有 Qwen3.8 要求 template_effort_changes 为 true。fix-index 备份原索引、不改权重字节；报 Unrecognized mapping 就停止，不随意改名。

单机小模型不经启动器，直接在本机起服务，另开一个标签发探针。它验证安装与模板，也为第22章提供单机对照。

```bash
python worker.py serve --model models/small --port 8080
# 另一个标签 / another tab
python lab.py probe --urls http://127.0.0.1:8080 --max-tokens 2048
```

> 通过：completed 为 true，答案为 42；然后 Control+C。q8 单机放不下（约29.5GB 对 16GB），不要在单机上试。

## 21 · 全集群接入与名单

*Join the cluster and build hostfiles*

11-03 09:00 之后，其余六台接线（DM5 搬入），按第04–14章完成设置，各跑 T0 与 T1，标准同第19章。然后在 mini01 用 peer 模式测其余六台（T2）。

```bash
bash scripts/netprobe.sh peer <IP2> <IP3> <IP4> <IP5> <IP6> <IP7>
```

通过：丢包 0，hops 为 1（同一二层），22 端口 open。第14章 iperf3 相邻机器应接近 940 Mbit/s；低于约 600 先查是否绕经学校核心网，或某根线只协商到百兆（media 显示 100baseTX）。

按第17章从 mini01 经局域网分发权重并校验。node0、DM5 没有外置 SSD 时只拷 small 与 q4。

建立名单时 SSH 与 IP 两栏都填以太网 IP。名单第一台是 rank 0，API 在它上面。

```bash
python lab.py hosts eth2.json      # mini01-02
python lab.py hosts eth4.json      # mini01-04
python lab.py check-hosts hosts/eth4.json
python lab.py launch ping hosts/eth4.json
```

> 通过：每个节点打印 PASS，nodes 与 sum 等于台数。其余名单到对应章节再建，每份都先 ping 再用。

## 22 · 校准：小模型 1/2/4 台流水线开销

*Calibrate pipeline overhead with 1, 2 and 4 nodes*

旧版只做了双机，缺单机基线。用同一个 small 模型、同一组参数测 1、2、4 台，直接量出每多一段流水线、每个 token 多花多少时间。这个数用来解释 A4，也用来判断第42章的微批流水线值不值得做。

```bash
# 单机，在 mini01 / one node on mini01
python worker.py bench --model models/small --prompt-tokens 2048 \
  --generation-tokens 512 --batch-size 1 --num-trials 5 \
  --prefill-step-size 512
# 双机与四机 / two and four nodes
python lab.py launch bench hosts/eth2.json --model small --parallel pp
python lab.py launch bench hosts/eth4.json --model small --parallel pp
```

每条命令自动预热 1 次再测 5 次。从 5 行 Trial 取 generation_tps 的中位数，记为 tps1、tps2、tps4。每段开销（毫秒/token）=（1/tps_n − 1/tps1）÷（n − 1）× 1000。

解读：A4 每个 token 约 300 毫秒（估算）。若每段开销只有几毫秒，A4 慢主要是带宽限制，属正常；若到几十毫秒，流水线本身就是瓶颈，先回到第14章和 T2 查网络。

> 小模型每个 token 的计算极短，开销占比会显得很大。只用这里的绝对毫秒数，不要把比例直接套到 27B。

## 23 · A4：四台 8-bit 流水线基线

*A4: four-node 8-bit pipeline baseline*

A4 是所有比较的基线；没有 A4 结果，后面的阶段都不开始。四台都要有同一 q8 目录且哈希一致。每台先读出默认 GPU 工作集上限并记下，不要修改它。

```bash
python -c "import mlx.core as mx; f=getattr(mx,'device_info',None) or mx.metal.device_info; print(f())"
```

```bash
# 每个参与节点 / each node
python lab.py monitor
# mini01
python lab.py launch serve hosts/eth4.json --model q8 \
  --parallel pp --batch 1
```

MacBook：复制工具包（lab.py 与 tasks 目录即可，客户端只用 Python 标准库），设好 API 地址，探针两次，再跑 12 道入门题。

```bash
export API=http://<mini01以太网IP>:8080
python3 lab.py probe --urls $API
python3 lab.py eval --urls $API --out results/A4-smoke.jsonl --requests 12
```

通过：回答完整，四台内存稳定，测试期间 swap 没有持续增长。q8 四机估算每台约 7.2GB 权重。内存紧张时依次：关无关程序 → 并发 1、cache 0 → 短输入 → 换更多节点；仍不行就标记不可行（第45章）。

> 首次加载时间单独记一行。之后的速度数字只来自第24章基准和第34章实测。

## 24 · A4：引擎速度基准

*A4: engine benchmark*

先停止 HTTP 服务；基准与服务不能同时占同一批节点。固定版本的 benchmark 每次自动预热 1 次、再测 5 次；输入为随机 token，关闭 EOS 提前结束，目标生成 512 token，预填充分块 512。

```bash
python lab.py launch bench hosts/eth4.json --model q8 \
  --parallel pp --input-tokens 2048
python lab.py launch bench hosts/eth4.json --model q8 \
  --parallel pp --input-tokens 8192
```

记录每次的 prompt_tps、generation_tps、total_time，从 5 行 Trial 手算中位数、最小、最大。peak_memory 只来自 rank 0，其他节点看各自的 monitor。异常退出则整轮作废。

对照估算：generation 约 3–3.7 tok/s 属预期范围。明显更低时先查：是否有节点在换页、是否有线只协商到百兆、是否有下载或别的任务在跑。

预填充受算力限制：2K 输入估计十几到几十秒，32K 可能要几分钟。32768 档只在 8192 稳定后测（第35章）。

> 这里的 tok/s 是引擎能力，不是用户等待时间；真实任务的思考长度不同，见第34章。

## 25 · 闸门 0：all_sum 微基准

*Gate 0: all_sum micro-benchmark*

张量并行每个 token 约要 128 次同步，每次约 10KB。以太网 TCP 上这种小消息的延迟没有公开数据，所以先花一晚量出来，再决定第26章和第42章阶段 3 做不做。在 mini01 新建纯文本 allsum.py，复制到 mini02–04 的同一路径。

```bash
import time, statistics, mlx.core as mx
g = mx.distributed.init(backend='ring', strict=True)
x = mx.ones((5120,), dtype=mx.float16)          # about 10 KB
def run(stream, n=1000):
    for _ in range(50): mx.eval(mx.distributed.all_sum(x, stream=stream))
    t = []
    for _ in range(n):
        s = time.perf_counter()
        mx.eval(mx.distributed.all_sum(x, stream=stream))
        t.append((time.perf_counter() - s) * 1e3)
    t.sort(); return [round(v, 3) for v in (statistics.median(t), t[989], t[-1])]
for name, st in [('cpu', mx.cpu), ('gpu', mx.gpu)]:
    try: r = run(st)
    except Exception as e: r = repr(e)[:80]
    if g.rank() == 0: print(f'nodes={g.size()} stream={name} median/p99/max_ms={r}')
```

```bash
for h in hosts/eth2.json hosts/eth4.json; do
  .venv/bin/mlx.launch --hostfile $h --backend ring \
    --python .venv/bin/python --cwd $PWD -- $PWD/allsum.py
done
```

| 中位数 / Median | 结论 / Decision |
|---|---|
| < 约0.5 ms | 张量并行值得试：做 B4e，保留框架阶段 3 / Try TP |
| 0.5–2 ms | B4e 可试但预期有限 / Limited upside |
| > 约2 ms | 放弃张量并行，只做流水线类优化 / Drop TP |

> 测量期间不跑别的任务。CPU 与 GPU 两种流分别记录；GPU 一栏报错或卡住超过 1 分钟，按 Control+C，记为“不支持”，不算失败。

## 26 · B4e（条件）：以太网四机张量并行

*B4e (conditional): four-node TP over Ethernet*

只在第25章中位数低于约 2ms 时做。与 A4 相同的四台、相同 q8，唯一变化是 --parallel tp；批量、精度、推理强度都不改。

```bash
python lab.py launch serve hosts/eth4.json --model q8 \
  --parallel tp --batch 1
# MacBook：probe 两次，再跑 12 道入门题 / probe twice, then 12 starter tasks
# 停止服务后跑基准 / stop the server, then benchmark
python lab.py launch bench hosts/eth4.json --model q8 \
  --parallel tp --input-tokens 2048
```

与 A4 的 generation_tps 对比。Apple 在 TB5 RDMA 上测得四机 TP 约为单机 2.6–3 倍，但那依赖 RDMA；以太网 TCP 上可能不到 2 倍，也可能不如流水线，以实测为准。

TP 改变了归约顺序，浮点舍入会不同。B4e 若要作为速度候选入选，必须和 A4 一样跑第28章质量筛选。

> 工具包只允许 2 或 4 路 TP；双机 q8 TP 内存余量不足，不做。

## 27 · 候选配置与执行顺序

*Candidate matrix and order*

| 编号 / ID | 模型与结构 / Layout | 角色 / Role |
|---|---|---|
| A4 | 8-bit，4台PP | 基线，最先做 / Baseline, first |
| B4e | 8-bit，4台TP，以太网 | 条件：闸门0 / If Gate 0 passes |
| E2 | 4-bit，2台PP，三组同时跑 | 提前到A4之后 / Moved up |
| R7s | BF16，7台PP，只跑必要题 | 质量参考 / Reference subset |
| C3 | 8-bit，3台PP | D33的前置容量测试 / Gate for D33 |
| D33 | 8-bit，两组三台PP | 并发候选 / Throughput |
| E3 | MoE，另一个模型 | 可选，A4之后 / Optional |

顺序：A4 → 闸门0 →（B4e）→ A4 质量筛选 → E2 → R7s → 等待时间与长上下文 → C3/D33 与负载 → 稳定性 → 决策。E2 只占两台，单流约是 q8 的 2 倍，三组可同时跑，所以提前。

磁盘闸门：q8 29.5GB，bf16 54.7GB。node0 与 DM5 放不下 q8：D33 需要其中一台有外置 SSD，R7s 需要两台都有。没有 SSD 就把这两项记为“未执行”，不换别的模型凑数。

BF16、8-bit、4-bit 可能来自不同转换流程，比较的是这几份具体文件，差异不能全部归因于位数。6-bit、mxfp8 等新格式不在本轮。

## 28 · 质量筛选：用批处理跑 60 题

*Quality screen with batching*

正确率与批大小基本无关，所以质量筛选用批处理，一轮约从 20 小时缩到 6–8 小时（估算）。所有候选用同一批大小、同一并发、同一输出预算和 xhigh，不加 --unique。

```bash
# mini01
python lab.py launch serve hosts/eth4.json --model q8 \
  --parallel pp --batch 4
# MacBook
python3 lab.py eval --urls $API --tasks tasks/quality60.jsonl \
  --requests 60 --concurrency 4 --max-tokens 8192 \
  --out results/A4-quality-r1.jsonl
```

batch 4 稳定（无持续换页）后可以改成 8，但一旦改了，所有候选都用 8，写进计划。中途内存出问题就回到 4，不混用。

预算耗尽（finish_reason=length）单独标记，不当作答错。某类题经常 length，就对所有候选统一提高预算，重测那一类。

采样有随机性。第一轮后，对 A4 与 E2 结果不同的题各重复至少 3 次；正式比较时每个候选的题目集合与重复次数相同，交错运行。

> 开跑前先算好结束时间，不要跨进共用方的备用窗口（11-06 至 11-10）。

## 29 · 评分

*Score outputs without fooling yourself*

summarize 会生成 .review.csv，在 Finder 里双击用 Numbers 打开。id 是这次请求的编号，task_id 是题号，两者都不要改。

```bash
python3 lab.py summarize results/A4-quality-r1.jsonl
```

对照 tasks/rubrics.csv：pass 填 1 或 0；critical_error 填 1 表示严重错误（如虚构关键证据、错误的破坏性文件操作建议），否则填 0。notes 写原因。pass 空白表示未评分。

代码题：把代码放进单独的练习文件夹，先读，再用题目给的边界例子测试；不要在真实项目里直接运行。工具题只评决策与参数。

盲评：请另一个人把结果标成 A/B，对照表私下保存，评完再揭晓。导出为新文件，如 A4-scores.csv，保持列名与 UTF-8。

> 工具只在全部请求评分齐全、编号匹配时才输出质量统计；未完成的请求必须填 0，严重错误一律按失败计。

## 30 · 如何加入自己的真实任务

*Add representative real tasks*

最简单的方法：用纯文本编辑器复制quality60.jsonl中的一行，给新任务唯一id，替换messages里的content和rubric。JSONL是一行一个完整JSON对象；字符串换行必须写成\n。

```bash
{"id":"REAL001","messages":[{"role":"user",
"content":"Your task here"}],"rubric":"Pass rule here"}
```

上框为了阅读分成两行；保存JSONL时合并为一行。TextEdit必须选择“格式 → 制作纯文本”，关闭智能引号，保存扩展名.jsonl。不要保存成富文本.rtf。

题目构成应像未来用途：代码修复、长文档、中文写作、工具参数等按实际比例安排。题目与答案分开保管，发送给模型的messages不要包含标准答案。

独立任务指不同问题，不是把同一个问题改十个数字。评分规则先写，后运行模型。关键任务设“一票否决”规则；普通任务用总通过率。

本指南自带脚本只发送messages和可选tools，不发送rubric。你的新题先用1个请求试读，再跑全量。

```bash
python3 lab.py eval --urls $API --tasks tasks/mytasks.jsonl \
  --requests 1 --out results/custom-check.jsonl
```

## 31 · E2：4-bit 双机，三组同时跑

*E2: three two-node 4-bit groups at once*

mini01 下载 q4（16.1GB），preflight、hash，再分发到 mini02–06 并校验（第16–17章）。双机 4-bit 每台约 8GB 权重，开 monitor 看余量。

```bash
python lab.py download q4
python lab.py preflight q4
python lab.py hash q4
```

建三份名单：eth12（mini01、02）、eth34（mini03、04）、eth56（mini05、06），各自 ping。每份第一台是该组 API。在 mini01 的三个标签里分别启动，批大小与第28章相同：

```bash
python lab.py launch serve hosts/eth12.json --model q4 --batch 4
python lab.py launch serve hosts/eth34.json --model q4 --batch 4
python lab.py launch serve hosts/eth56.json --model q4 --batch 4
```

MacBook 对三个地址分别 probe，再一起跑质量筛选。客户端按请求轮流分给三组，并发设为各组 batch 之和。

```bash
python3 lab.py eval --tasks tasks/quality60.jsonl \
  --urls http://<IP1>:8080,http://<IP3>:8080,http://<IP5>:8080 \
  --requests 60 --concurrency 12 --max-tokens 8192 \
  --out results/E2-quality-r1.jsonl
```

> E2 是效率对照：过了第33章质量门，才进入速度和并发比较。三组合计估算 40–70 tok/s，未测。

## 32 · BF16 参考：只跑必要的题

*BF16 reference on a planned subset*

BF16 七机一题可能要一个多小时（估算），不全量跑。参考集 = 事先固定的抽样子集 ∪ A4/E2 有差异或不确定的题。抽样子集必须在看到任何 A4 结果之前生成并保存。

```bash
mkdir -p plans
python3 - <<'EOF'
import json, random
ids = [json.loads(l)['id'] for l in open('tasks/quality60.jsonl')]
pick = sorted(random.Random(20261030).sample(ids, 15))
open('plans/R7-fixed.txt', 'w').write('\n'.join(pick) + '\n'); print(pick)
EOF
```

A4、E2 评分后，把“两者结果不同、重复中忽对忽错、或有严重错误”的题号逐行写进 plans/R7-extra.txt，再合成任务文件：

```bash
python3 - <<'EOF'
import json
ids = set(open('plans/R7-fixed.txt').read().split()) | set(open('plans/R7-extra.txt').read().split())
keep = [l for l in open('tasks/quality60.jsonl') if json.loads(l)['id'] in ids]
open('tasks/R7-subset.jsonl', 'w').writelines(keep)
open('plans/R7-ids.txt', 'w').write('\n'.join(sorted(ids)) + '\n'); print(len(keep))
EOF
```

R7s 需要七台都有 bf16：node0、DM5 把 models/bf16 建成指向外置 SSD 的符号链接。下载、preflight、hash 同第20章；名单 eth7 含 mini01–07；批大小同第28章；--requests 填上面打印的题数。

```bash
python lab.py launch serve hosts/eth7.json --model bf16 --batch 4
python3 lab.py eval --urls $API --tasks tasks/R7-subset.jsonl \
  --requests <题数> --concurrency 4 --out results/R7s-r1.jsonl
```

> 七台仍无法稳定承载时，记“BF16 未完成”，不编造参考分数；性能测试照常，但不能声称量化无损。

## 33 · 配对比较与质量门

*Paired comparison and the quality gate*

A4 与 E2 都跑了全集，可以直接比较。和 R7s 比较时，先把评分表裁到同一批题号（裁出 *-scores-R7.csv）：

```bash
python3 - <<'EOF'
import csv
ids = set(open('plans/R7-ids.txt').read().split())
for c in ['A4', 'E2']:
    rows = list(csv.DictReader(open(f'results/{c}-scores.csv', encoding='utf-8-sig')))
    with open(f'results/{c}-scores-R7.csv', 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader()
        w.writerows(r for r in rows if r['task_id'] in ids)
EOF
```

```bash
python3 lab.py paired results/A4-scores.csv results/E2-scores.csv
python3 lab.py paired results/R7s-scores.csv results/A4-scores-R7.csv
```

| 情况 / Case | 结论 / Decision |
|---|---|
| 可复现的新增严重错误 | 淘汰该配置 / Reject |
| 下降不超过 2 个百分点 | 通过（容忍度事先定） / Pass; tolerance fixed in advance |
| 区间跨过门槛 | “不确定”：加真实独立任务，或保留高精度 / Uncertain |
| R7s 未完成 | 只比较 A4 与 E2，不说无损 / No lossless claim |

工具按题聚合后报告配对差异与 bootstrap 区间；重复次数不一致会报错。共用材料的题彼此相关，区间只是描述，不能证明无损。

> R7s 里有一部分题是因为“有差异”才被挑中的，会放大差距。结论分两行报告：只用 plans/R7-fixed.txt 再裁一次得到的无偏一行，加全部 R7s 题一行。

## 34 · 用户等待时间：batch=1

*User waiting time at batch=1*

这一项必须 batch=1、cache=0、并发 1，才代表一个用户真实要等多久。全量 60 题在 A4 上估计约 20 小时，所以用事先固定的等待时间子集：每类 3 题，共 15 题，看结果前生成。

```bash
python3 - <<'EOF'
import json, random
rows = [json.loads(l) for l in open('tasks/quality60.jsonl')]
rng = random.Random(1030); keep = []
for cat in sorted({r['category'] for r in rows}):
    keep += rng.sample([r for r in rows if r['category'] == cat], 3)
open('tasks/latency15.jsonl', 'w').writelines(json.dumps(r, ensure_ascii=False) + '\n' for r in keep)
EOF
```

```bash
python lab.py launch serve hosts/eth4.json --model q8 --parallel pp --batch 1
python3 lab.py eval --urls $API --tasks tasks/latency15.jsonl \
  --requests 15 --concurrency 1 --out results/A4-latency-r1.jsonl
```

| 字段 / Field | 含义 / Meaning |
|---|---|
| first_chunk_s | 首个内容块，可能是思考 / First chunk, may be reasoning |
| first_answer_s | 首个最终答案块；空值=无法可靠测量，不是0 / Null means unmeasurable |
| duration_s | 发送到结束的总时长 / Send to stream end |
| finish_reason | stop 完成；length 预算耗尽 / stop or length |

速度赢家只在过了质量门的配置中选：比较完成时间的中位数和最慢几题；改善小于约 10% 且波动重叠时，选更简单或更高精度的。E2、B4e 用同一 latency15 重复。

> 客户端无法区分服务端排队和计算时间，本工具包不伪造这两项。

## 35 · 长上下文逐档增加

*Increase context length gradually*

make_long.py 用 Qwen 自己的分词器生成带目标记录的文本，并报告含聊天模板后的实际输入 token 数；2K、8K、32K 是目标档位，不保证整齐。它需要模型文件，所以在 mini01 生成，再复制到 MacBook 的 tasks 目录。

```bash
python make_long.py --tokens 2048 --out tasks/long2k.jsonl
python make_long.py --tokens 8192 --out tasks/long8k.jsonl
python make_long.py --tokens 32768 --out tasks/long32k.jsonl
```

先 2K，再 8K，最后 32K，前一档稳定才进下一档。每个文件有 6 条任务，目标信息分别在前、中、后。

```bash
python3 lab.py eval --urls $API --tasks tasks/long8k.jsonl \
  --requests 6 --concurrency 1 --out results/A4-long8k.jsonl
```

Qwen3.8-27B 是混合架构：64 层中约四分之一是全注意力，其余是 Gated DeltaNet，KV 缓存比同尺寸稠密模型小很多。32K、64K 很可能可行，但要测。64K 用 --tokens 65536 和新文件名。

> 上下文总量包括输入、历史、思考和答案。这些题只测容量、检索与速度，不代表全部长上下文能力。

## 36 · 单组服务的并发阶梯

*Closed-loop concurrency ladder*

选过了质量门的 8-bit 配置。服务端 batch 调到 2，客户端并发 2；再试 4、8。每次改服务参数都先停旧服务。批处理的实测增益在别处只有 2.6–3.7 倍，远低于“批大小倍”。

```bash
python lab.py launch serve hosts/eth4.json --model q8 \
  --parallel pp --batch 2
# MacBook
python3 lab.py eval --urls $API --tasks tasks/quality60.jsonl \
  --requests 120 --concurrency 2 --unique \
  --out results/A4-c2.jsonl
```

closed 模式等一个请求完成再补发。--unique 给每个请求加不同但可复现的编号，同一任务顺序在不同配置上输入相同；同时保持 cache=0。加了编号的成绩不要和不加编号的质量成绩直接比。

每档至少 15 分钟，不足就加 requests。完成样本少于 100 时工具不报告 P95；100 个也只有约 5 个尾部样本，重要结论要更多样本和重复轮次，同时报告失败率。

> 通过率下降、持续换页或等待明显超期时停止加压。固定 seed 或 KV 量化可能让服务端走非批处理路径，本实验不启用。

## 37 · C3 与 D33：两组三台

*C3 and D33: two three-node replicas*

前提：mini06（DM5）已用外置 SSD 放好 q8。先做 C3：名单 eth3（mini01–03），在目标输入长度和 batch 下稳定运行。三机 q8 每台约 9.6GB 权重，余量比四机小。

C3 稳定后建 eth123（mini01–03）与 eth456（mini04–06，mini04 必须在第一行），各自 ping。mini07 空闲，MacBook 当客户端。

```bash
python lab.py launch serve hosts/eth123.json --model q8 --batch 2
# mini01 另一个标签 / another mini01 tab
python lab.py launch serve hosts/eth456.json --model q8 --batch 2
```

```bash
python3 lab.py eval --tasks tasks/quality60.jsonl \
  --urls http://<mini01-IP>:8080,http://<mini04-IP>:8080 \
  --requests 120 --concurrency 4 --unique \
  --out results/D33-c4.jsonl
```

客户端按请求轮流分给两组，这是可重复的简单策略，不是智能网关。和 A4 同并发的结果对比；估算两组合计约 16–25 tok/s，一组四机约 9–14，均未测。

> 三机 8-bit 在真实上下文下不稳定，或 DM5 没有 SSD，D33 直接淘汰，保留四机方案；不为“每台都用上”压缩系统余量。

## 38 · 固定到达率与有用吞吐

*Open-loop arrivals and useful throughput*

固定并发会掩盖排队，因为客户端一直在等。open 模式按固定间隔发请求，不管旧请求是否完成。rate 单位为请求/秒：0.02 即每 50 秒一条。从低开始，每次乘 1.5 或 2，期限内成功率下降或在途数持续增长就停。

```bash
python3 lab.py eval --urls $API --tasks tasks/quality60.jsonl \
  --mode open --rate 0.02 --concurrency 16 \
  --requests 120 --unique --out results/A4-rate002.jsonl
```

open 模式的 concurrency 是客户端在途上限；满了就记 client_inflight_limit，作为未接纳请求，不藏进无限队列。比较配置时任务、请求数、到达率和上限都要相同。

先定期限（例如 600 秒，按用途在测试前写下），评分后带评分重算。correct_on_time_per_hour = 期限内答对数 ÷ 整轮秒数 × 3600，整轮包括排队与最后排空。

```bash
python3 lab.py summarize results/A4-rate002.jsonl --deadline 600 \
  --scores results/A4-rate002-scores.csv
```

> 过载也是有效结果：保留失败数、截断数和期限违约。没有评分文件时工具输出 quality_scored=false，不给有用吞吐；tokens/s 不等于质量。

## 39 · 两小时与八小时稳定性

*Two-hour and eight-hour stability*

前两名配置各跑至少 2 小时；胜出者再跑 8 小时混合任务。用已测可承受的到达率，不用过载点。全程开 monitor。8 小时轮次不要跨进共用方的任何运行窗口。

open 模式的发出时长约为 (requests − 1) ÷ rate。rate=0.02 时 577 个请求约 8 小时，之后还要排空。

```bash
python3 lab.py eval --urls $API --tasks tasks/quality60.jsonl \
  --mode open --rate 0.02 --concurrency 16 \
  --requests 577 --unique --out results/soak-8h.jsonl
```

看开头、中间、结尾：内存是否越来越大，速度是否逐步下降，有没有永远不结束的请求。每次异常记时间，保留所有节点的 logs。

重启恢复另做：停掉一个副本，看客户端记录失败；恢复后重新 probe。另测一次关掉客户端连接后服务能否继续处理新请求。

> 接纳标准：无崩溃、无永久挂起、无持续增长的内存。完成率 99% 的目标需要足够样本；小样本 8 小时零失败不等于证明了 99.9%。

## 40 · 可选：缓存、推理强度与 MoE

*Optional: cache, reasoning effort and MoE*

缓存：只把入围配置的 cache 改为 4，连续发完全相同的请求，看 usage 中 cached_tokens 是否增加；命中与未命中分开报告。缓存占额外内存；轮询客户端不做会话固定。

推理强度：同一配置用 --effort medium 重跑 latency15。权重不变，思考长度可能变；更快只算行为取舍，不算硬件提速。

| E3：Qwen3.6-35B-A3B | 每台常驻 / per Mac | 单流估算 / Stream est. |
|---|---|---|
| 8-bit，4台流水线 | 约9GB，接近上限 | 15–20 tok/s |
| 4-bit，3台流水线 | 约7GB | 25–30 tok/s |

E3 是另一个模型（MoE，35B 总参数、3B 激活），比较的是模型而不是精度：新建模型队列，冻结 revision，过同一道质量门。先确认固定版本的 mlx-lm 支持它的流水线（preflight），再冻结。

> E3 的代价：并发时优势缩小，约 8 个请求就会触及全部专家；适合延迟优先，不适合堆吞吐。工具包没有内置它，要在 lab.py 的 MODELS 里加一项。

## 41 · 最终选择与归档

*Make the final decision*

| 优先级 / Priority | 规则 / Rule |
|---|---|
| 1 严重错误 / Critical | 可复现的新增严重错误淘汰 / Reject |
| 2 质量差距 / Gap | 下降不超过 2 个百分点，报告不确定性 / ≤2pp with uncertainty |
| 3 稳定 / Stability | 崩溃、挂起、持续换页淘汰 / Reject crashes, hangs, paging |
| 4 速度 / Latency | latency15 完成更快 / Faster real completion |
| 5 并发 / Throughput | 期限内答对更多 / More correct on time |
| 6 相近时 / Tie | 优先高精度与简单部署 / Prefer precision, simplicity |

2 个百分点是事先定的容忍度，不是技术定律。区间跨过门槛时结论是“不确定”；“无显著差异”不等于相等。

最后保留两行：速度优先配置、并发优先配置，可能相同；只能由实测决定。同时写下是否进入第42章的阶段 0 之后的工作。

归档：PDF、工具包、依赖锁、模型锁、hostfile、netprobe 输出、plans 目录、所有节点日志、原始结果、评分表、总结。副本放外置盘，不删工作目录。

## 42 · 延伸：特化框架的阶段与闸门

*Extension: a specialised framework, stages and gates*

distributed-llama 与 prima.cpp 已是面向低端家用集群的框架，但都不支持 Gated DeltaNet 混合架构，也没有 MLX/Metal GPU 路径，更没有 7 台基础款 M4 加千兆网的公开实测。下面是否值得做，由 A4 与闸门 0 的实测决定。

| 阶段 / Stage | 内容 / Work | 闸门 / Gate |
|---|---|---|
| A | 官方 MLX 跑完 A4 | 没有基线不进入后续 / Baseline first |
| 0 | all_sum 与 1/2/4 机校准（第22、25章） | <约0.5ms可做TP；>约2ms放弃TP |
| 1 | 7 段流水线微批 | 与 mlx-lm 流水线逐 token logits 一致 |
| 2 | 推测解码（Qwen3.8 自带 MTP）与 DeltaNet 状态回滚 | 输出分布不变；接受率与端到端速度 |
| 3 | 张量并行 + 8-bit 压缩同步（条件） | 阶段0通过；量化同步质量单独测 |

估算收益（乐观上限）：微批流水线总吞吐约 25 到 60–90 tok/s，单请求速度不变；张量并行单请求乐观 7–10 tok/s，悲观无提升；叠加推测解码乐观 15–20 tok/s。均未测。

验证：27B q8 单机放不下，没有单机参考。先在同系列能单机放下的小模型（如 Qwen3.5-9B）上开发和验证，再对 27B 做逐 token logits 对比。

> 自研框架不能替代对照基线：始终保留官方 MLX 的 A4 结果，实验对象从“模型与硬件”变成“我们的代码”。

## 57 · 附录：测试路线修订记录

*Appendix: test-route revision record*

修订日期 2026-10-30。依据项目仓库 mac-mini-llm-lab 的项目简报与网络配置方案。第03–17章、购买、术语、故障排查与 Thunderbolt 内容未改，只调整章号；第02、18–42章重写。

| 旧版 / Before | 本版 / Now |
|---|---|
| mini07 当控制机 | MacBook 当客户端，七台只做计算 |
| 先 BF16 全量参考 | BF16 只跑固定抽样 + 有差异的题 |
| 质量与延迟同一轮 batch=1 | 质量批处理 4–8；延迟用 latency15，batch=1 |
| 双机小模型 | 1/2/4 台校准流水线开销 |
| Thunderbolt 上比较 PP 与 TP | 闸门 0 微基准；条件做以太网 TP（B4e） |
| 4-bit 最后可选 | E2 提前，三组双机同时跑 |
| 无时间预算与共用约束 | 估算时间表；共用窗口；T0–T2 网络探测 |
| 无 MoE 与框架路线 | E3 可选队列；特化框架阶段与闸门 |

验证范围：新增的几段 Python 片段（抽样、裁表）已用 quality60.jsonl 离线跑通；allsum.py 与所有集群命令尚未在机器上运行。文中所有速度与时间均为估算。

- [Apple ML Research: distributed inference with MLX and RDMA](https://machinelearning.apple.com/research/mlx-distributed-inference)
- [MLX releases](https://github.com/ml-explore/mlx/releases)
- [mlx-lm releases](https://github.com/ml-explore/mlx-lm/releases)
- [vllm-mlx (arXiv 2601.19139)](https://arxiv.org/html/2601.19139)
- [prima.cpp (arXiv 2504.08791)](https://arxiv.org/html/2504.08791v2)
- [Project repository: mac-mini-llm-lab](https://github.com/YinChingZ/mac-mini-llm-lab)
