# cleanup_research_cron.sh 研究文档

## 场景与职责

`cleanup_research_cron.sh` 是研究自动化系统的清理工具脚本，负责在研究工作全部完成后清理 crontab 中注册的定时任务。它是研究 guard 系统的配套组件，用于实现研究生命周期的完整闭环管理。

### 核心职责

1. **定时任务清理**：从用户 crontab 中移除与研究相关的定时条目
2. **状态记录**：记录清理操作完成状态到 state 文件
3. **日志记录**：记录清理操作到日志文件便于审计

### 使用场景

- 当 `blueprint_checklist.md` 中所有项目都被标记为完成时
- 当 `AUTO_CLEANUP_ON_COMPLETE=1` 时由 `research_guard.sh` 自动触发
- 手动执行以停止研究自动化流程

## 功能点目的

### 1. 安全执行控制

脚本要求显式传入 `--execute` 参数才会执行清理操作，防止误操作：

```bash
if [[ "${1:-}" != "--execute" ]]; then
  echo "usage: $0 --execute"
  exit 1
fi
```

### 2. ripgrep 兼容性处理

脚本提供 `rg` 命令的降级方案，在没有安装 ripgrep 时使用 grep -E 替代：

```bash
if ! command -v rg >/dev/null 2>&1; then
  rg() {
    grep -E "$@"
  }
fi
```

### 3. 精确的 crontab 条目匹配

使用正则表达式精确匹配需要移除的脚本路径：

```bash
filtered_cron="$(printf '%s\n' "$current_cron" | rg -v "${REPO_ROOT}/\\.ops/(generate_daily_research_todo\\.sh|research_guard\.sh)" || true)"
```

匹配目标：
- `.ops/generate_daily_research_todo.sh` - 每日待办生成脚本
- `.ops/research_guard.sh` - 研究守护主脚本

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 参数校验 (--execute)                                      │
│    └─ 失败则输出 usage 并退出                                │
├─────────────────────────────────────────────────────────────┤
│ 2. 获取当前 crontab                                          │
│    └─ crontab -l 2>/dev/null || true                        │
├─────────────────────────────────────────────────────────────┤
│ 3. 过滤掉研究相关条目                                         │
│    └─ rg -v 排除匹配的行                                     │
├─────────────────────────────────────────────────────────────┤
│ 4. 写回 crontab                                              │
│    └─ sed 删除空行 | crontab -                              │
├─────────────────────────────────────────────────────────────┤
│ 5. 记录状态                                                  │
│    └─ 写入 STATE_FILE 和 LOG_FILE                           │
└─────────────────────────────────────────────────────────────┘
```

### 关键数据结构

#### 路径变量

| 变量 | 值 | 用途 |
|------|-----|------|
| `REPO_ROOT` | `$(cd "$(dirname "$0")/.." && pwd)` | 仓库根目录 |
| `LOG_DIR` | `$REPO_ROOT/.cron` | 日志目录 |
| `STATE_FILE` | `$LOG_DIR/research_cleanup.state` | 状态文件 |
| `LOG_FILE` | `$LOG_DIR/research_cleanup.log` | 日志文件 |

#### 日志格式

```
[YYYY-MM-DD HH:MM:SS +/-ZZZZ] <message>
```

示例：
```
[2026-03-22 10:00:00 +0800] removed research cron entries for /home/sansha/Github/codex
```

### 核心命令解析

#### crontab 操作

```bash
# 读取当前 crontab
current_cron="$(crontab -l 2>/dev/null || true)"

# 过滤并写回
printf '%s\n' "$filtered_cron" | sed '/^\s*$/d' | crontab -
```

- `sed '/^\s*$/d'`：删除空行，避免 crontab 中出现不必要的空行
- `crontab -`：从 stdin 读取新的 crontab 内容

## 关键代码路径与文件引用

### 本脚本位置

```
.ops/cleanup_research_cron.sh
```

### 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `.ops/research_guard.sh` | 调用方 | 在 `AUTO_CLEANUP_ON_COMPLETE=1` 时自动调用 |
| `.ops/generate_daily_research_todo.sh` | 被引用 | 在清理目标中被移除的定时任务 |
| `.cron/research_cleanup.state` | 输出 | 清理完成状态 |
| `.cron/research_cleanup.log` | 输出 | 清理操作日志 |

### 调用链

```
research_guard.sh (检测到所有任务完成)
    └──> cleanup_research_cron.sh --execute
            ├──> 读取 crontab
            ├──> 过滤条目
            ├──> 写回 crontab
            ├──> 写入 state 文件
            └──> 写入 log 文件
```

## 依赖与外部交互

### 系统依赖

| 依赖 | 用途 | 降级方案 |
|------|------|----------|
| `crontab` | 读取/写入用户定时任务 | 无，必须 |
| `rg` (ripgrep) | 正则过滤 | `grep -E` |
| `date` | 时间戳生成 | 无，必须 |
| `mkdir` | 创建日志目录 | 无，必须 |

### 环境变量

脚本不依赖特定环境变量，但读取以下变量：

| 变量 | 来源 | 用途 |
|------|------|------|
| `$1` | 命令行参数 | 必须为 `--execute` |
| `$0` | 脚本名 | 计算 REPO_ROOT |

### 文件系统交互

```
读取:
  ~/.crontab (通过 crontab -l)

写入:
  .cron/research_cleanup.state
  .cron/research_cleanup.log
```

## 风险、边界与改进建议

### 风险点

#### 1. crontab 并发修改风险

**问题**：脚本不是原子操作，如果用户同时手动修改 crontab，可能导致竞态条件。

**缓解**：操作迅速（毫秒级），风险较低。

#### 2. 正则匹配过于严格

**问题**：如果 crontab 中的路径使用了软链接或相对路径，可能无法匹配。

**示例**：
```bash
# 无法匹配以下条目（使用相对路径）
0 9 * * * cd /home/sansha/Github/codex && bash .ops/research_guard.sh
```

#### 3. 无备份机制

**问题**：清理前不备份原 crontab，误删后无法恢复。

### 边界情况

| 场景 | 行为 |
|------|------|
| 无 crontab | `crontab -l` 返回空，清理空内容，正常退出 |
| 无匹配条目 | 原样写回，无副作用 |
| crontab 被其他进程锁定 | 依赖 `crontab` 命令的内部处理 |
| 日志目录不存在 | `mkdir -p` 自动创建 |

### 改进建议

#### 1. 添加备份机制

```bash
# 清理前备份
crontab -l > "$LOG_DIR/crontab.backup.$(date +%s).txt" 2>/dev/null || true
```

#### 2. 支持软链接路径匹配

```bash
# 使用 readlink 解析实际路径
REPO_ROOT_REAL="$(readlink -f "$REPO_ROOT")"
# 同时匹配原始路径和真实路径
```

#### 3. 添加确认提示

```bash
# 显示将要移除的条目，要求确认
echo "Will remove the following entries:"
printf '%s\n' "$current_cron" | rg "${REPO_ROOT}/\\.ops/(generate_daily_research_todo\\.sh|research_guard\.sh)" || true
read -p "Confirm? [y/N] " confirm
[[ "$confirm" == "y" ]] || exit 0
```

#### 4. 支持 dry-run 模式

```bash
case "${1:-}" in
  --execute) ;;  # 实际执行
  --dry-run)    # 仅显示将要移除的条目
    printf '%s\n' "$current_cron" | rg "${REPO_ROOT}/\\.ops/..."
    exit 0
    ;;
  *)
    echo "usage: $0 --execute|--dry-run"
    exit 1
    ;;
esac
```

#### 5. 更精确的日志记录

```bash
# 记录实际移除了多少条目
removed_count=$(printf '%s\n' "$current_cron" | rg -c "${REPO_ROOT}/\\.ops/..." || echo 0)
log "removed ${removed_count} research cron entries for ${REPO_ROOT}"
```

### 安全建议

1. **权限检查**：确保脚本只能由仓库所有者执行
2. **审计日志**：记录执行者信息（`whoami`, `$SSH_CONNECTION` 等）
3. **时间窗口限制**：可选配置仅在特定时间段允许清理
