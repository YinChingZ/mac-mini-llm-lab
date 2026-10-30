# mac-mini-llm-lab

在 7 台基础款 Apple M4 Mac mini（16 GB，千兆以太网）上，按《七台 Mac mini 本地 LLM 实验指南》测量 Qwen3.8-27B 的质量、速度、并发与稳定性，并评估是否值得做针对该硬件的推理优化。

状态：草案，尚未开始实测。

## 文档

- [docs/PROJECT-BRIEF.md](docs/PROJECT-BRIEF.md)：项目简报。目标与边界、硬件与共用约束、时间线、对指南的复核、类似实践证据、性能估算、MoE 方向、特化框架的阶段与闸门。
- [docs/NETWORK-CONFIG-PLAN.md](docs/NETWORK-CONFIG-PLAN.md)：交换机与学校网络的配置方案和测试计划。
- [docs/TEST-ROUTE.md](docs/TEST-ROUTE.md)：重排后的测试路线（2026-10-30），对应 PDF 修订版第02、18–42章；基础设施章节只在 PDF 中。
- [docs/MINIMAL-FLOW.md](docs/MINIMAL-FLOW.md)：最简实验流程，只保留得出结论必须做的 11 步。

## 脚本

- [scripts/netprobe.sh](scripts/netprobe.sh)：只读网络探测（`snapshot` / `egress` / `peer`）。不改设置，不读钥匙串，不带密钥。

## 约定

- 只写实测数字；未测的留空。文档中的速度与内存数字除非标明"实测"，都是估算。
- 模型权重、原始响应、日志、密钥、含 IP 或账号的文件不进入 git（见 `.gitignore`）。
- 机器与另一个项目共用，对方运行期间只允许只读操作，详见简报 §2。
