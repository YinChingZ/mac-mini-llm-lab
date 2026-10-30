<!-- Generated from the PDF source (tmp/pdfs/new_route.py); edit the source, not this file. -->
# 最简实验流程（2026-10-30）

只保留得出结论必须做的步骤。“第NN章”指完整指南 PDF 及 [TEST-ROUTE.md](TEST-ROUTE.md) 的章号。所有时间与 tok/s 为估算，命令尚未在机器上运行。

## 最简实验流程

*Minimal experiment flow · 2026-10-30*

目的：用最少的步骤回答三个问题。① 四机 8-bit 流水线（A4）能不能稳定跑；② 4-bit（E2）的质量能不能接受；③ 一个用户实际要等多久、集群能扛多少负载。

| # | 步骤 / Step | 何时何地 / When, where | 详见 / Full guide |
|---|---|---|---|
| 1 | T0 只读快照，MAC 交学校 | 现在，七台 | 第19章 |
| 2 | T1；安装、冻结、下载 small 与 q8 | 10-30 16:00 后，DM7=mini01 | 第08–09、15–16、20章 |
| 3 | 接线设置；T2；分发并校验权重 | 11-03 09:00 后，全部 | 第04–17、21章 |
| 4 | A4 启动、探针、12 道入门题 | mini01–04 + MacBook | 第23章 |
| 5 | A4 引擎基准（2048 一档） | mini01–04 | 第24章 |
| 6 | A4 质量 60 题（batch 4）并评分 | 约6–8小时（估算） | 第28–29章 |
| 7 | E2 三组 4-bit 质量 60 题，配对比较 | mini01–06 | 第31、33章 |
| 8 | latency15：batch=1 等待时间 | A4；E2 若过质量门 | 第34章 |
| 9 | 并发 4 一档 | 入选配置 | 第36章 |
| 10 | 2 小时稳定性 | 胜出配置 | 第39章 |
| 11 | 决策与归档 | — | 第41章 |

其余全部可选（见最后一页）。不跑 BF16 就不能说“量化无损”；不跑闸门 0 就对张量并行没有结论。

> 规则不变：只写实测数字；共用机器在 11-03 09:00 前只读；长测试不跨进 11-06 至 11-10 的备用窗口；版本固定 MLX 0.32.2。

## 步骤 1–3 · 准备

*Steps 1-3 · Preparation*

1　七台各跑一次只读快照（netprobe.sh 在项目仓库的 scripts 目录）。共用期间只做这一步。

```bash
bash scripts/netprobe.sh snapshot | tee "netprobe-$(hostname -s)-T0.txt"
```

2　DM7（当作 mini01）接交换机后跑 T1；通过标准：captive_portal=none、各站点不是 000、TLS 0 失败、MTU 通过。然后按第08–09、15–16章安装、冻结版本、下载 small 与 q8，并 preflight。

```bash
bash scripts/netprobe.sh egress | tee "netprobe-$(hostname -s)-T1.txt"
python lab.py freeze-models
python lab.py download small && python lab.py download q8
python lab.py preflight q8
```

3　11-03 09:00 后其余六台接线，完成第04–14章；从 mini01 跑 T2，再分发 q8 到 mini02–04 并校验哈希（第17章）。

```bash
bash scripts/netprobe.sh peer <IP2> <IP3> <IP4> <IP5> <IP6> <IP7>
python lab.py hosts eth4.json        # SSH 与 IP 都填以太网 IP
python lab.py launch ping hosts/eth4.json
```

> 通过：peer 丢包 0、hops 为 1；ping 打印 nodes=4、sum=4.0。不通过就先修网络，不要往下走。

## 步骤 4–5 · A4 基线

*Steps 4-5 · A4 baseline*

4　mini01–04 各开 monitor，mini01 启动 A4。MacBook 只需复制 lab.py 与 tasks 目录（客户端只用 Python 标准库）。

```bash
python lab.py monitor                          # mini01-04 各一次
python lab.py launch serve hosts/eth4.json --model q8 --batch 1   # mini01
```

```bash
export API=http://<mini01以太网IP>:8080                       # MacBook
python3 lab.py probe --urls $API
python3 lab.py eval --urls $API --out results/A4-smoke.jsonl --requests 12
```

通过：回答完整，四台内存稳定，测试期间 swap 不持续增长。首次加载时间单独记。

5　停掉服务，跑一次引擎基准。从 5 行 Trial 取 generation_tps 中位数；估算范围约 3–3.7 tok/s，明显更低先查换页与网线。

```bash
python lab.py launch bench hosts/eth4.json --model q8 --input-tokens 2048
```

> A4 不通过就停在这里：它是所有比较的基线。

## 步骤 6–7 · 质量

*Steps 6-7 · Quality*

6　质量用批处理跑（正确率与批大小基本无关）。A4 与 E2 必须用同一 batch、并发、输出预算，都不加 --unique。

```bash
python lab.py launch serve hosts/eth4.json --model q8 --batch 4      # mini01
python3 lab.py eval --urls $API --tasks tasks/quality60.jsonl \
  --requests 60 --concurrency 4 --out results/A4-quality-r1.jsonl
python3 lab.py summarize results/A4-quality-r1.jsonl                  # 评分表
```

按 rubrics.csv 在 review.csv 里填 pass（1/0）与 critical_error，另存为 A4-scores.csv。length 结束的单独标记，不当作答错。

7　下载 q4、preflight、分发到 mini01–06；建 eth12、eth34、eth56 三份名单，各启动一组，MacBook 一起跑：

```bash
python lab.py launch serve hosts/eth12.json --model q4 --batch 4   # eth34、eth56 同样
python3 lab.py eval --tasks tasks/quality60.jsonl --requests 60 --concurrency 12 \
  --urls http://<IP1>:8080,http://<IP3>:8080,http://<IP5>:8080 \
  --out results/E2-quality-r1.jsonl
python3 lab.py paired results/A4-scores.csv results/E2-scores.csv
```

> 质量门：有可复现的新增严重错误就淘汰；下降不超过 2 个百分点算通过；区间跨过 2 个百分点记“不确定”，保留 A4。

## 步骤 8–11 · 等待、负载、稳定与决策

*Steps 8-11 · Waiting, load, stability, decision*

8　等待时间必须 batch=1、并发 1。用固定的 15 题子集（每类 3 题，在看结果前生成），A4 跑一遍；E2 过了质量门再跑一遍。

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
python lab.py launch serve hosts/eth4.json --model q8 --batch 1      # mini01
python3 lab.py eval --urls $API --tasks tasks/latency15.jsonl \
  --requests 15 --concurrency 1 --out results/A4-latency-r1.jsonl
```

9　入选配置用 batch 4、并发 4 跑一档负载（至少 15 分钟）；10　胜出配置跑 2 小时固定到达率（145 个请求 × 每 50 秒一条），全程 monitor，看内存是否增长、有无挂起。

```bash
python3 lab.py eval --urls $API --tasks tasks/quality60.jsonl \
  --requests 120 --concurrency 4 --unique --out results/WIN-c4.jsonl
python3 lab.py eval --urls $API --tasks tasks/quality60.jsonl --mode open \
  --rate 0.02 --concurrency 16 --requests 145 --unique --out results/WIN-soak2h.jsonl
```

> 11　决策：先看严重错误和质量差距，再看稳定，最后看等待时间与负载；相近时选更高精度、更简单的。归档锁文件、名单、netprobe 输出、日志、原始结果和评分表。

## 可以跳过的部分

*What the minimal flow skips*

| 跳过 / Skipped | 跳过的代价 / Cost of skipping | 何时补做 / Add when |
|---|---|---|
| 小模型 1/2/4 台校准 | A4 慢时分不清是带宽还是网络 | A4 明显低于估算 |
| 闸门 0 与 B4e（张量并行） | 对 TP 没有结论 | 想要单请求更快 |
| BF16 参考（R7s） | 不能说“量化无损” | 要写精度结论；需两块外置SSD |
| 长上下文 2K/8K/32K | 不知道长输入能否稳定 | 实际用途有长文档 |
| 并发阶梯 2/4/8、开放到达 | 不知道负载上限 | 要多人同时使用 |
| C3 与 D33 两组三机 | 不知道双副本吞吐 | DM5 有外置 SSD 且需要吞吐 |
| 8 小时浸泡 | 只证明 2 小时内稳定 | 准备长期部署 |
| 缓存、推理强度、MoE、特化框架 | — | 主线结论之后 |

补做任何一项，都回到完整指南对应章节，用相同的固定版本与命名规则，结果加到同一个归档里。

> 这份流程里的时间与 tok/s 都是估算；所有命令尚未在七台机器上实际运行。
