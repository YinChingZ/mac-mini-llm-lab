# Mac mini LLM Lab：项目简报

2026-10-30，草案。网络与配置见 [NETWORK-CONFIG-PLAN.md](NETWORK-CONFIG-PLAN.md)，测试脚本见 [`scripts/netprobe.sh`](../scripts/netprobe.sh)。

**所有速度和内存数字，除非标明"实测"，都是按硬件规格推算的估算，只能用来排期，不能写进结论。**

---

## 1. 目标与边界

**主线**：按《七台 Mac mini 本地 LLM 实验指南》（2026-09-14，以下简称 PDF）第一部分，在 7 台基础款 M4 上测出 Qwen3.8-27B 的质量、速度、并发和稳定性，选出部署配置，所有结果可复查。

**延伸（待闸门决定）**：评估并在值得时构建针对"基础款 M4 加千兆以太网加混合架构模型"的推理优化：流水线微批、推测解码，条件成立时再做张量并行。

**边界**：
- 机器与另一个研究项目共用，在对方运行期间不得影响它（见 §2）。
- 只写实测数字；未测的留空，不用估算代替（沿用 PDF 原则）。
- 自研框架不能替代对照基线：必须先有官方 MLX 的 A4 结果。

## 2. 硬件现状与共用约束

| 项目 | 现状 |
|---|---|
| 机器 | 7 台 Mac mini（基础款 M4：10 核 CPU / 10 核 GPU，16 GB 统一内存，带宽 120 GB/s）+ 1 台 MacBook 管理端 |
| 系统 | 七台均为 macOS 15.3.1，已一致，**不升级**（升级换不来 RDMA，只会增加风险） |
| 网络 | 六台目前用 Wi-Fi；第七台（DM5）在异地，将并入同一交换机网络。拟接入学校分配的 IP，具体方案待定 |
| 磁盘空闲 | 约 25 GB（node0）、33 GB（DM5）、89–204 GB（其余五台）；q8 权重 29.5 GB，bf16 54.7 GB。node0 与 DM5 放不下 q8，需要外置 SSD |
| Thunderbolt | 基础款 M4 只有 TB4，RDMA 需要 TB5 与 macOS 26.2，**不适用**。目前没有 TB 线计划 |

**共用约束**：另一个研究项目占用其中六台，运行窗口至 2026-11-03 09:00（备用窗口 11-06 至 11-10，是否冲突待确认）。在此期间：
- 这六台只允许只读操作（如 `netprobe.sh snapshot`），不接线、不重启、不升级、不改主机名、不新建账户、不下载大文件、不跑 MLX；
- 第七台（DM7）在 10-30 16:00 之后可自由使用，作为下载机和试验机。

## 3. 时间线

| 时间 | 事项 |
|---|---|
| 10-30 16:00 起 | DM7 接交换机，跑 `netprobe.sh` T1，装 lab 账户、Homebrew、uv、MLX 0.32.2，冻结模型版本，下载 small 与 q8，单机 small 探针 |
| 11-03 09:00 起 | 其余六台接线，T2 测试；从 DM7 局域网分发权重；PDF 第 04–20 章 |
| 11-03 之后 | PDF A4（四机 q8 流水线）基线、小模型 1/2/4 机校准、质量 60 题 |
| 之后 | §8 的阶段 0 微基准与闸门 |

## 4. 对 PDF 方案的复核

方向没有过时，需要补的是：

1. **没有时间预算。** 单请求解码受带宽限制，q8 流水线约 3–3.7 tok/s，8192 token 的输出约 37–45 分钟；quality60 在 xhigh 加并发 1 下，一个配置约需 1–2 天，BF16 参考更久。
2. **质量筛选与延迟测量分开。** 正确率与批大小基本无关，质量筛选可用批处理 4–8；只有"用户真实等待时间"保持 batch=1。
3. **BF16 参考只对必要的题跑**：A4 有差异或不确定的题，加一个事先固定的抽样子集，写进计划，不能事后挑。
4. **版本继续固定**：MLX 0.32.2 与 PDF 记录的 mlx-lm 提交。MLX 现为 0.32.4、mlx-lm 为 0.32.2，其改动主要是 RDMA 修复与个别量化 bug，不影响以太网加 8-bit。要测 mxfp8 等新格式时另建新版本队列，不在原队列里中途升级。q4 权重在 9-14 更新过，冻结时核对 revision。
5. **补一个校准步骤**：用 small 模型分别跑 1、2、4 台流水线，直接量出以太网流水线的开销（PDF 第 20 章只做了双机，缺单机基线）。
6. **用 MacBook 当客户端**，七台都只做计算。
7. **不要强行调高 GPU 内存上限**；先实测默认的 `max_recommended_working_set_size`。
8. **E2（4-bit 双机）提前到 A4 之后**：单流速度约为 q8 的 2 倍，只占 2 台，可并行 3 组。
9. 研究私有数据与外部项目的数据不得为腾出磁盘而删除。

## 5. 类似实践的证据

没有找到 7 台基础款 M4 加千兆以太网加 27B 稠密模型的公开好结果。有明确好结果的，硬件都是 Ultra 加 TB5 RDMA。

| 案例 | 配置 | 结果 | 说明 |
|---|---|---|---|
| Apple 官方研究 | M5/M3 Ultra Mac Studio，TB5 RDMA，Qwen3.8-27B BF16 | 单机 19.69；两机流水线 19.44（**不提速**）；两机张量并行 33.27；四机张量并行 50.89 tok/s | 实测，同一模型，硬件差得远。单机约为带宽理论上限的 90% |
| distributed-llama | 4 台 M4 Pro mini（24 GB），Llama 3.3 70B Q40，张量并行 | 单机 3.2 → 四机 11.4 tok/s | 转述数据；网络类型未写明，CPU 路径，节点数须为 2 的幂 |
| prima.cpp（ICLR 2026） | 家用异构设备，环形流水线加预取，Wi-Fi | 70B：674 ms/token；32B 配推测解码 26 tok/s | 面向单请求，不含 Gated DeltaNet 架构 |
| exo 早期演示 | 4 台 M4 mini 加 1 台 M4 Max，Qwen2.5 Coder 32B | 18 tok/s | 自述，配置含 M4 Max |
| heise | 4 台 M4 Pro mini，TB5，Nemotron 70B 4-bit | 8 tok/s | 无单机对照 |
| Ziskind（经 AppleInsider） | 5 台 M4 mini，Thunderbolt | 一台 M4 Pro 好过两台 M4 联机 | 无数字 |
| 个人博客 | 2 台 16GB mini，TB，Qwen 32B 4-bit | 内存吃满，exo 崩溃 | 无 tok/s |
| vllm-mlx 论文 | 单台 M4 Max，连续批处理 | 16 并发：8B 提速 2.6 倍，0.6B 提速 3.7 倍 | 实测，但硬件与模型不同 |

## 6. 性能估算（全部为估算）

**单个请求**（带宽 120 GB/s；Apple 数据显示 MLX 单机可达上限的约 90%）

| 配置 | 估算 tok/s | 8192 token 约需 |
|---|---|---|
| q8，3 或 4 台流水线 | 3–3.7 | 37–45 分钟 |
| bf16，7 台流水线 | 1.6–1.9 | 72–85 分钟 |
| q4，2 台流水线 | 5–6.5 | 21–27 分钟 |
| q8，4 台张量并行 | **未知**：Apple 的 2.6–3.0 倍依赖 RDMA，TB4/以太网走 TCP 未见任何数据，可能不到 2 倍，也可能不如流水线 | — |

流水线加机器不会让单个请求变快。单请求提速只有三条路：张量并行、降低精度、换成 MoE。

**多个请求同时跑**（批处理的实测增益只有 2.6–3.7 倍，远低于理想的"批大小倍"）

| 方案 | 全集群合计 |
|---|---|
| 一组四机 q8 | 约 9–14（另外三台闲着） |
| 两组三机 q8（D33） | 约 16–25 |
| 三组双机 q4 | 约 40–70（前提是 4-bit 过质量门） |

一个排期用的例子：quality60 假设平均输出 4000 token，共约 24 万 token；单并发约 20 小时，批处理 4–8 约 6–8 小时。

**预填充**（长输入）受算力限制，估计每秒几十个输入 token。2K 输入十几到几十秒，32K 可能要几分钟；流水线对预填充有一定帮助（Apple 数据：64K 时两机约 1.8 倍）。

**内存**：q8 四机每台约 7.2 GB，三机约 9.6 GB，双机放不下；bf16 七机约 7.8 GB。Qwen3.8-27B 是混合架构（64 层中约 1/4 为全注意力，其余为 Gated DeltaNet），KV 缓存比同尺寸稠密模型小很多，32K、64K 档位很可能可行，需要测。

## 7. MoE 方向

候选：Qwen3.6-35B-A3B（35B 总参数，3B 激活；上一代模型，Qwen3.8 系列没有 MoE）。

| 配置 | 每台常驻 | 单流估算 | 对 q8 稠密 |
|---|---|---|---|
| 8-bit，4 台流水线 | 约 9 GB，接近上限 | 15–20 tok/s | 约 5 倍 |
| 4-bit，3 台流水线 | 约 7 GB | 25–30 tok/s | 约 8 倍 |

依据：8-bit 每 token 约读 3.3 GB，上限约 36 tok/s；二手转述称 M4 Pro 上 MLX 4-bit 实测 81.79 tok/s，约为上限的一半多（MoE 是零散读取，效率低），按 50–60% 折算后再扣流水线开销。

代价：
1. **并发时优势缩小**：一批请求里激活的专家数随批量增长，约 8 个请求就能触及 64 选 8 模型的全部专家；MoE 适合延迟优先，不适合靠大并发堆吞吐。
2. **16GB 单机放不下**：有人在 16GB M4 mini 上跑 Qwen3.5-35B-A3B（3-bit，llama.cpp，mmap，专家从 SSD 换页）约 17 tok/s，质量损失没评估，不是可依赖的路线。
3. **它是另一个模型**：比较的是模型而不是精度，需新建模型队列并过同一道质量门。没有可靠的公开数据比较它与 Qwen3.8-27B 的质量。
4. 先确认固定版本的 mlx-lm 支持该模型的流水线，再冻结。

建议作为可选队列 E3，排在 A4 之后。

## 8. 特化框架：是否值得做

**先例**：distributed-llama（张量并行，同步数据压成 8-bit）和 prima.cpp（环形流水线、预取、推测解码）已经是"面向低端家用集群"的框架，所以"没人尝试"不成立。**空白**：它们都不支持 Gated DeltaNet 混合架构；没有 MLX/Metal GPU 路径上的版本；没有 7 台基础款 M4 加千兆网的实测发布。

**可能的收益（乐观上限，取决于阶段 0）**

| 做法 | 估算 | 说明 |
|---|---|---|
| 7 段流水线微批：多个微批同时在途，每台都满载 | 总吞吐约 25（每微批 batch=1）到 60–90（每微批 batch 4–8） | 每条请求的速度不变；不改数值，最容易验证 |
| 张量并行 + 8-bit 压缩同步 | 乐观 7–10 tok/s（单请求），悲观无提升 | 每 token 128 次同步，每次约 10 KB；成本主要在 Metal 同步，不在带宽 |
| 推测解码（Qwen3.8 自带 MTP，块大小 3） | 叠加其他做法后乐观 15–20 tok/s | 接受率未知；DeltaNet 是循环状态，猜错要回滚，状态大小固定，每步存快照可行 |

**阶段与闸门**

| 阶段 | 内容 | 闸门 |
|---|---|---|
| A | 按 PDF 跑完 A4 基线（官方 MLX） | 没有基线，不进入后续阶段 |
| 0 | 微基准（约一晚）：①两台机器间对 10 KB fp16 张量做 1000 次 `mx.distributed.all_sum`，记录中位数与 P99；②small 模型 1/2/4 机流水线开销 | 全规约中位数 < 约 0.5 ms：张量并行值得做；> 约 2 ms：放弃张量并行，只做阶段 1、2 |
| 1 | 流水线微批 | 与 mlx-lm 流水线逐 token 对比 logits 一致 |
| 2 | 推测解码与 DeltaNet 状态回滚 | 输出分布不变（拒绝采样的正确性检验）；接受率与端到端速度 |
| 3 | 张量并行（条件） | 阶段 0 通过；量化同步的质量单独测 |

**验证方式**：27B q8 单机放不下，没有单机参考。可以先在同系列、能单机放下的小模型（如 Qwen3.5-9B）上开发和验证，再对 27B 做 logits 逐 token 对比。

**粗略工作量**（我的估计，可交给 Codex 会话实现，审查与调试仍需人）：阶段 1 约 1–2 周；阶段 2 约 2–4 周；阶段 3 约 2–4 周。

**风险**：
- 正确性验证是硬骨头；量化同步会引入误差，要单独测质量。
- 实验对象从"模型与硬件"变成"我们的代码"，必须保留官方 MLX 对照。
- 机器时间受共用约束限制。

## 9. 网络与配置

见 [NETWORK-CONFIG-PLAN.md](NETWORK-CONFIG-PLAN.md)（学校网络五种情况、T0/T1/T2 测试）与 [`scripts/netprobe.sh`](../scripts/netprobe.sh)（只读，不改设置，不碰钥匙串，不带密钥）。要点：先收集七个 MAC 地址；DM7 试点；机器之间用 IP 而不是 `.local`；SSH 与计算流量可分开。

## 10. 待确认

- 学校网络：DHCP 还是静态 IP；是否登记 MAC、门户登录或 802.1X；七个端口是否同一 VLAN、是否开端口隔离；出口是否放行 Hugging Face、GitHub、PyPI、Homebrew。
- 另一个项目的运行是否会顺延到备用窗口，与本项目"下周"的冲突如何处理。
- node0 与 DM5 的外置 SSD 是否购买。
- 阶段 0 的测量用哪两台机器，什么时候做。

## 11. 来源

- [Apple ML Research: Local and Distributed Large LLM Inference with MLX and RDMA](https://machinelearning.apple.com/research/mlx-distributed-inference)
- [MLX releases](https://www.Github.com/ml-explore/mlx/releases)、[mlx-lm releases](https://github.com/ml-explore/mlx-lm/releases)
- [mlx-community Qwen3.8 collection](https://huggingface.co/collections/mlx-community/qwen38)、[Qwen3.8-27B-MTP-8bit](https://huggingface.co/mlx-community/Qwen3.8-27B-MTP-8bit)
- [Alibaba releases Qwen3.8-27B (DataNorth)](https://datanorth.ai/news/alibaba-releases-qwen3-8-27b)
- [Apple 社区：RDMA over Thunderbolt 4](https://discussions.apple.com/thread/256216267)
- [exo review (PromptQuorum)](https://www.promptquorum.com/power-local-llm/exo-review)
- [VentureBeat：exo labs 与 Mac M4 集群](https://venturebeat.com/ai/you-can-now-run-the-most-powerful-open-source-ai-models-locally-on-mac-m4-computers-thanks-to-exo-labs)
- [heise：Nemotron 70B on four Mac minis M4 Pro](https://heise.de/-10015283)
- [AppleInsider：M4 Mac minis in a computing cluster](https://appleinsider.com/articles/24/11/25/m4-mac-minis-in-a-computing-cluster-is-an-incredibly-cool-project-but-not-hugely-effective)
- [Running LLM on mac mini clusters, strategy and practice](https://xichen1997.github.io/posts/2025-02-27-running-llm-on-mac-mini-clusters-strategy-and-practice/)
- [vllm-mlx：Native LLM and MLLM Inference at Scale on Apple Silicon](https://arxiv.org/html/2601.19139)
- [distributed-llama 指南](https://blog.brightcoding.dev/2025/08/29/turn-your-home-devices-into-an-ai-supercomputer-a-hands-on-guide-to-distributed-llama)
- [prima.cpp (arXiv 2504.08791)](https://arxiv.org/html/2504.08791v2)
- [NVIDIA：Dense vs MoE](https://developer.nvidia.com/blog/dense-vs-moe-models-active-parameters-throughput-and-when-to-choose-each/)
- [Lynx：MoE 批量感知专家选择](https://arxiv.org/pdf/2411.08982)
- [Running Qwen 3.6 locally on a Mac mini M4 16GB](https://resume-website-ds0.pages.dev/blog/running-qwen-locally-mac-mini-m4)
