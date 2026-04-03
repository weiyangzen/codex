# research_guard.sh 研究文档

## 场景与职责

`research_guard.sh` 是研究自动化系统的核心守护进程脚本，负责协调和管理整个代码仓库的自动化研究流程。它实现了基于锁的任务调度、并行工作器管理、Kimi AI 集成、Git 自动提交等完整功能，是驱动大规模代码研究的基础设施。

### 核心职责

1. **任务调度**：从 blueprint checklist 中认领和分配研究任务
2. **并行执行**：通过 tmux 管理多个并行工作器
3. **AI 集成**：调用 Kimi CLI 执行实际的研究任务
4. **状态管理**：维护研究进度、锁状态和检查点
5. **Git 集成**：自动提交研究成果，支持冲突解决

### 使用场景

- **自动化研究**：作为 cron 定时任务持续执行研究
- **批量处理**：处理大型代码库的系统化研究
- **并行加速**：利用多工作器并行处理多个文件/目录
- **无人值守**：支持长时间运行的自动化研究流程

## 功能点目的

### 1. 多层级锁机制

脚本实现了四种锁文件，确保并发安全：

| 锁文件 | 用途 | 范围 |
|--------|------|------|
| `LOCK_FILE` | 单实例执行锁 | 本地工作器 |
| `SCHEDULER_LOCK_FILE` | 调度器锁 | tmux 工作器管理 |
| `CLAIM_LOCK_FILE` | 任务认领锁 | 任务分配 |
| `WRITE_LOCK_FILE` | 写入锁 | checklist 更新 |

### 2. 任务认领系统

实现基于文件的分布式任务认领：

```bash
# 认领文件格式: <owner_token>\t<pid>\t<created_timestamp>\t<key>
claim_create_under_lock() {
  local key="$1"
  local token="$2"
  local claim_file
  claim_file="$(claim_file_for_key "$key")"
  [[ -f "$claim_file" ]] && return 1
  printf '%s\t%s\t%s\t%s\n' "$token" "$$" "$(date +%s)" "$key" > "$claim_file"
}
```

### 3. 批次处理策略

文件按目录批次处理，控制总大小：

```bash
MAX_BATCH_BYTES=102400  # 100KB 批次上限

# 同目录文件合并批次，直到达到大小限制
if (( batch_count > 0 )) && (( batch_total_bytes + cand_size > MAX_BATCH_BYTES )); then
  break
fi
```

### 4. 多 Key 轮换机制

支持多个 Kimi API Key 自动轮换：

```bash
read_kimi_keys() {
  KIMI_KEYS=()
  if [[ ! -f "$KIMI_KEYS_FILE" ]]; then
    return 1
  fi
  # 解析 key 文件，支持注释
  while IFS= read -r line || [[ -n "$line" ]]; do
    key="$(trim "${line%%#*}")"
    [[ -n "$key" ]] || continue
    KIMI_KEYS+=("$key")
  done < "$KIMI_KEYS_FILE"
}
```

### 5. 自动冲突解决

Git 推送失败时自动 rebase 并解决冲突：

```bash
auto_push_with_conflict_resolution() {
  # 1. 尝试直接推送
  # 2. 失败则 fetch + rebase
  # 3. 冲突时 checkout --ours 保留本地变更
  # 4. 重试推送，最多 3 次
}
```

## 具体技术实现

### 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                         research_guard.sh                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   main()    │  │  Scheduler  │  │      Worker Loop        │  │
│  │             │  │             │  │                         │  │
│  │ TMUX_WRAP=1 │──│ ensure_tmux │──│   run_worker_loop       │  │
│  │             │  │  _workers() │  │       │                 │  │
│  │ WORKER_MODE │  │             │  │       ▼                 │  │
│  │    =1       │──│   (bypass)  │──│  run_worker_once        │  │
│  └─────────────┘  └─────────────┘  │       │                 │  │
│                                    │       ▼                 │  │
│  ┌─────────────┐  ┌─────────────┐  │  claim_next_task        │  │
│  │   Locks     │  │  Kimi Exec  │  │       │                 │  │
│  │             │  │             │  │       ▼                 │  │
│  │ 4 lockfiles │──│run_research │──│  build_task_prompt      │  │
│  │             │  │  _with_kimi │  │       │                 │  │
│  └─────────────┘  └─────────────┘  │       ▼                 │  │
│                                    │  run_research_with_kimi │  │
│  ┌─────────────┐  ┌─────────────┐  │       │                 │  │
│  │   Claims    │  │  Git Ops    │  │       ▼                 │  │
│  │             │  │             │  │  verify_reports_nonempty│  │
│  │ claim files │──│   commit    │──│       │                 │  │
│  │             │  │   push      │  │       ▼                 │  │
│  └─────────────┘  └─────────────┘  │ apply_success_updates   │  │
│                                    └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 关键流程

#### 主流程

```
main()
├── TMUX_WRAP=1 && WORKER_MODE!=1
│   └── ensure_tmux_workers()  # 启动 tmux 工作器
│       ├── 获取 scheduler 锁
│       ├── 检查 tmux 可用性
│       └── 循环创建/重启窗口
└── WORKER_MODE=1 || TMUX_WRAP!=1
    └── run_worker_loop()  # 工作器主循环
        ├── 生成 token
        ├── 检查 kimi 可用性
        └── while true
            └── run_worker_once()
                ├── refresh_checklist_with_lock()
                ├── claim_next_task()
                ├── build_task_prompt()
                ├── run_research_with_kimi()
                ├── verify_reports_nonempty()
                ├── apply_success_updates_with_lock()
                └── release_claims()
```

#### 任务认领流程

```
claim_next_task(token, claims_out, items_out, meta_out)
├── 获取 claim 锁
├── cleanup_stale_claims_under_lock()  # 清理过期认领
├── 读取待处理条目
├── 遍历待处理条目
│   ├── 检查是否已被认领
│   ├── DIR: 直接认领，单任务返回
│   └── FILE: 同目录批次收集
│       ├── 检查文件大小
│       ├── 检查批次大小限制
│       └── 添加到批次
└── 返回批次信息
```

### 关键数据结构

#### 环境变量配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `AUTO_CLEANUP_ON_COMPLETE` | `0` | 完成后自动清理 cron |
| `KIMI_EXEC_TIMEOUT_SECONDS` | `1200` | Kimi 执行超时（秒） |
| `AUTO_PUSH_ON_CHECKPOINT` | `0` | 自动推送到远程 |
| `MAX_BATCH_BYTES` | `102400` | 批次大小上限 |
| `TMUX_WRAP_ENABLED` | `1` | 启用 tmux 包装 |
| `TMUX_SESSION_NAME` | `$PROJECT` | tmux 会话名 |
| `MAX_PARALLEL_RESEARCH` | `4` | 最大并行工作器数 |
| `KIMI_MODEL` | `k2p5` | 使用的模型 |
| `CLAIM_TTL_SECONDS` | `7200` | 认领过期时间（秒） |

#### 认领文件格式

```
<owner_token>\t<pid>\t<created_timestamp>\t<key>

示例:
codex-slot1-12345-1711094400\t12345\t1711094400\tFILE:src/main.rs
```

#### items.tsv 格式

```
<line_no>\t<TYPE>\t<path>\t<report_path>\t<size>

示例:
615\tFILE\t.ops/generate_daily_research_todo.sh\tDocs/researches/.ops/generate_daily_research_todo.sh_research.md\t1851
```

#### meta.env 格式

```bash
MODE='FILE_BATCH'
TARGET_DESC='FILE_BATCH .ops (4 files, 34176 bytes)'
COMMIT_TITLE='FILE_BATCH .ops (4 files)'
BATCH_COUNT='4'
BATCH_TOTAL_BYTES='34176'
```

### 提示词模板

脚本根据任务类型生成不同的提示词：

#### DIR 任务提示词

```
请研究DIR <path>。

你在项目仓库根目录工作。请完成以下任务并直接修改文件：
1) 深入阅读目标对象与其上下文依赖...
2) 产出详尽研究文档到：<report>
...
```

#### FILE_SINGLE 任务提示词

```
请研究FILE <path>。
...
```

#### FILE_BATCH 任务提示词

```
请按同目录批次研究 FILE（总大小上限 <MAX_BATCH_BYTES> bytes）。

本批次文件如下（相近目录合并，避免过度零碎）：
- 行<line_no> | <path> | <report> | <size> bytes
...

你在项目仓库根目录工作。请完成以下任务并直接修改文件：
1) 逐个深入阅读本批次文件与其上下文依赖...
2) 为每个文件分别产出详尽研究文档到其对应路径...
```

## 关键代码路径与文件引用

### 本脚本位置

```
.ops/research_guard.sh
```

### 调用关系

```
调用:
  .ops/generate_research_blueprint_checklist.sh  # 生成/刷新清单
  .ops/generate_daily_research_todo.sh          # 生成每日 TODO
  .ops/cleanup_research_cron.sh                 # 清理 cron（条件）
  kimi                                          # AI 执行
  git                                           # 版本控制
  tmux                                          # 终端复用

被调用:
  cron (定时调度)
  手动执行
  自身递归 (tmux 工作器)
```

### 输入文件

| 文件 | 路径 | 说明 |
|------|------|------|
| blueprint_checklist.md | `Docs/researches/blueprint_checklist.md` | 任务清单 |
| kimi_keys.txt | `$HOME/kimi_keys.txt` | API Key 列表 |

### 输出文件

| 文件/目录 | 路径 | 说明 |
|-----------|------|------|
| 研究文档 | `Docs/researches/**` | 生成的研究文档 |
| 日志 | `.cron/research_guard.log` | 执行日志 |
| 状态 | `.cron/research_guard.state` | 当前状态 |
| 认领 | `.cron/research_claims/*.claim` | 认领文件 |
| 临时文件 | `.cron/*.XXXXXX` | 临时文件 |

### 状态机

```
                    ┌─────────────┐
                    │    start    │
                    └──────┬──────┘
                           ▼
              ┌────────────────────────┐
              │  refresh_checklist...  │
              └──────┬─────────────────┘
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    ┌────────┐ ┌──────────┐ ┌──────────┐
    │running │ │completed │ │  failed  │
    │ _exec  │ │          │ │_blueprint│
    └───┬────┘ └────┬─────┘ └────┬─────┘
        │           │            │
        ▼           │            ▼
   ┌─────────┐      │      ┌──────────┐
   │exec_comp│      │      │exec_fail │
   │ leted   │      │      │ed/timeout│
   └────┬────┘      │      └────┬─────┘
        │           │           │
        └───────────┴───────────┘
                    │
                    ▼
              ┌──────────┐
              │  blocks  │
              │  (0/1)   │
              └──────────┘
```

## 依赖与外部交互

### 系统依赖

| 依赖 | 用途 | 必需 |
|------|------|------|
| `bash` | 脚本执行 | 是 |
| `flock` | 文件锁 | 是 |
| `rg` (ripgrep) | 文本搜索 | 否（有降级） |
| `kimi` | AI 执行 | 是 |
| `git` | 版本控制 | 是 |
| `tmux` | 终端复用 | 否（有降级） |
| `sha1sum` | 哈希计算 | 是 |
| `date` | 时间戳 | 是 |
| `wc` | 计数 | 是 |
| `mktemp` | 临时文件 | 是 |
| `timeout` | 超时控制 | 是 |
| `kill` | 进程检查 | 是 |

### 外部服务

| 服务 | 用途 | 配置 |
|------|------|------|
| Kimi API | AI 研究执行 | `KIMI_BASE_URL`, `KIMI_MODEL` |
| Git 远程 | 代码推送 | 仓库配置 |

### 网络依赖

- Kimi API 调用需要网络连接
- Git 推送需要网络连接（如果启用）

## 风险、边界与改进建议

### 风险点

#### 1. 硬编码路径

**问题**：脚本包含大量硬编码路径，可移植性差。

```bash
CODEX_VENDOR_PATH="/home/sansha/.nvm/versions/node/v24.14.0/..."
KIMI_BIN="${KIMI_BIN:-/home/sansha/.local/bin/kimi}"
```

#### 2. 单点故障

**问题**：如果 research_guard.sh 进程崩溃，整个研究流程停止。

#### 3. 资源竞争

**问题**：多个仓库同时运行时，可能竞争系统资源（CPU、内存、API 配额）。

#### 4. Git 冲突风险

**问题**：自动冲突解决使用 `--ours` 策略，可能丢失远程变更。

#### 5. API 配额耗尽

**问题**：无 API 配额监控，可能因配额耗尽导致任务失败。

### 边界情况

| 场景 | 行为 |
|------|------|
| 所有任务完成 | 设置状态为 completed，可选清理 cron |
| Kimi 全部 Key 失败 | 返回错误，设置 block 计数 |
| 超时 | 返回 124，设置 exec_timeout 状态 |
| 报告文件为空 | 返回 67，标记任务失败 |
| tmux 不可用 | 降级为单工作器模式 |
| 无待处理任务 | 返回 2，设置 completed 状态 |

### 改进建议

#### 1. 配置外部化

```bash
# 使用配置文件替代硬编码
RESEARCH_CONFIG="${RESEARCH_CONFIG:-$REPO_ROOT/.researchrc}"
if [[ -f "$RESEARCH_CONFIG" ]]; then
  source "$RESEARCH_CONFIG"
fi
```

#### 2. 健康检查

```bash
# 添加心跳机制
heartbeat() {
  while true; do
    echo "$(date +%s)" > "$LOG_DIR/heartbeat"
    sleep 60
  done
}
```

#### 3. 资源限制

```bash
# 添加 CPU/内存限制
run_research_with_kimi() {
  (
    ulimit -t $CPU_LIMIT
    ulimit -v $MEMORY_LIMIT
    timeout "$KIMI_EXEC_TIMEOUT_SECONDS" "$KIMI_BIN" ...
  )
}
```

#### 4. 配额监控

```bash
# 跟踪 API 使用情况
track_quota() {
  local key_index="$1"
  local tokens_used="$2"
  echo "$(date +%s),$key_index,$tokens_used" >> "$LOG_DIR/quota_usage.csv"
}
```

#### 5. 优雅退出

```bash
# 捕获信号，清理资源
cleanup() {
  release_claims "$token" "$claims_file"
  rm -f "$claims_file" "$items_file" "$meta_file" "$prompt_file"
  exit 0
trap cleanup SIGTERM SIGINT
```

#### 6. 任务优先级

```bash
# 支持优先级队列
# 在 checklist 中添加优先级标记
# - [ ] [FILE:high] src/critical.rs
# - [ ] [FILE:low] docs/trivial.md
```

#### 7. 增量研究

```bash
# 支持基于 git diff 的增量研究
# 只研究变更的文件
incremental_research() {
  git diff --name-only HEAD~1 | while read file; do
    mark_file_for_research "$file"
  done
}
```

#### 8. 结果验证

```bash
# 添加研究质量检查
verify_research_quality() {
  local report="$1"
  # 检查必须章节是否存在
  for section in "场景与职责" "功能点目的"; do
    if ! grep -q "$section" "$report"; then
      return 1
    fi
  done
}
```

#### 9. 监控集成

```bash
# 支持 Prometheus metrics
emit_metric() {
  local name="$1"
  local value="$2"
  echo "# HELP research_${name}" >> "$LOG_DIR/metrics.prom"
  echo "# TYPE research_${name} gauge" >> "$LOG_DIR/metrics.prom"
  echo "research_${name} ${value}" >> "$LOG_DIR/metrics.prom"
}
```

#### 10. 分布式支持

```bash
# 支持多机器分布式研究
# 使用 Redis 或共享存储作为协调中心
distributed_claim_task() {
  curl -X POST "${COORDINATOR_URL}/claim" \
    -d "token=$token&slot=$WORKER_SLOT"
}
```

### 安全建议

1. **密钥管理**：使用密钥管理服务而非明文文件
2. **权限控制**：限制脚本执行权限，防止未授权访问
3. **审计日志**：记录所有关键操作和变更
4. **沙箱执行**：考虑在容器或沙箱中执行 AI 任务
5. **输入验证**：验证所有外部输入，防止注入攻击
