# generate_daily_research_todo.sh 研究文档

## 场景与职责

`generate_daily_research_todo.sh` 是研究自动化系统的每日待办生成器，负责基于 `blueprint_checklist.md` 的当前状态生成格式化的每日研究 TODO 文档。它为研究人员提供清晰的工作优先级视图，是研究 guard 系统的重要组成部分。

### 核心职责

1. **状态快照生成**：统计 checklist 中已完成和待处理的项目数量
2. **每日 TODO 生成**：创建带有日期标记的 Markdown 待办文档
3. **依赖管理**：在 checklist 不存在时自动触发生成

### 使用场景

- 每日开始研究工作时查看待办事项
- `research_guard.sh` 在完成每个任务后自动更新 TODO
- 手动执行以获取当前研究进度快照

## 功能点目的

### 1. 自动依赖触发

如果 checklist 文件不存在，脚本会自动调用生成器：

```bash
if [[ ! -f "$CHECKLIST_FILE" ]]; then
  bash "$REPO_ROOT/.ops/generate_research_blueprint_checklist.sh" >/dev/null
fi
```

### 2. 多维度统计

脚本从四个维度统计研究进度：

| 统计项 | 计算方式 | 用途 |
|--------|----------|------|
| `pending_total` | 未勾选的 `[DIR]` 和 `[FILE]` 项 | 总剩余工作量 |
| `done_total` | 已勾选的 `[x]` 项 | 已完成工作量 |
| `dir_pending` | 未勾选的 `[DIR]` 项 | 剩余目录研究数 |
| `file_pending` | 未勾选的 `[FILE]` 项 | 剩余文件研究数 |

### 3. 结构化输出

生成的 TODO 文档包含以下章节：

```markdown
# Research TODOs YYYYMMDD

## Snapshot
- Done: <count>
- Pending: <count>
- Pending Dirs: <count>
- Pending Files: <count>

## Pending Items
- [ ] [DIR|FILE] <path>
...
```

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 设置环境                                                  │
│    └─ PATH 包含 codex 和 node 工具链                        │
├─────────────────────────────────────────────────────────────┤
│ 2. 检查/生成 checklist                                       │
│    └─ 不存在则调用 generate_research_blueprint_checklist.sh │
├─────────────────────────────────────────────────────────────┤
│ 3. 统计进度数据                                              │
│    └─ 使用 rg 匹配不同状态的正则                            │
├─────────────────────────────────────────────────────────────┤
│ 4. 生成 TODO 文档                                            │
│    └─ 写入 Docs/researches/todos_YYYYMMDD.md                │
├─────────────────────────────────────────────────────────────┤
│ 5. 输出结果                                                  │
│    └─ 打印生成信息和文件路径                                │
└─────────────────────────────────────────────────────────────┘
```

### 关键数据结构

#### 路径变量

| 变量 | 值 | 说明 |
|------|-----|------|
| `CHECKLIST_FILE` | `$REPO_ROOT/Docs/researches/blueprint_checklist.md` | 输入文件 |
| `DATE_TAG` | `$(date +%Y%m%d)` | 日期标记（YYYYMMDD） |
| `TODO_FILE` | `$REPO_ROOT/Docs/researches/todos_${DATE_TAG}.md` | 输出文件 |

#### 正则匹配模式

| 模式 | 匹配内容 |
|------|----------|
| `^-\ \[\ \]\ \[(DIR\|FILE)\]\ ` | 未完成的 DIR/FILE 项 |
| `^-\ \[[xX]\]\ \[(DIR\|FILE)\]\ ` | 已完成的 DIR/FILE 项 |
| `^-\ \[\ \]\ \[DIR\]\ ` | 未完成的 DIR 项 |
| `^-\ \[\ \]\ \[FILE\]\ ` | 未完成的 FILE 项 |

### 统计实现细节

```bash
# 统计待处理总数
pending_total="$( (rg -n '^-\ \[\ \]\ \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"

# 统计已完成总数  
done_total="$( (rg -n '^-\ \[[xX]\]\ \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"
```

- `|| true`：确保 rg 无匹配时不会导致管道失败
- `tr -d ' '`：删除 wc 输出的前导空格

## 关键代码路径与文件引用

### 本脚本位置

```
.ops/generate_daily_research_todo.sh
```

### 输入文件

| 文件 | 路径 | 格式 |
|------|------|------|
| blueprint_checklist.md | `Docs/researches/blueprint_checklist.md` | Markdown checklist |

### 输出文件

| 文件 | 路径 | 格式 |
|------|------|------|
| todos_YYYYMMDD.md | `Docs/researches/todos_YYYYMMDD.md` | Markdown TODO |

### 调用关系

```
调用方:
  research_guard.sh
    └──> generate_daily_research_todo.sh
            ├──> (可选) generate_research_blueprint_checklist.sh
            └──> 输出 todos_YYYYMMDD.md

手动执行:
  $ bash .ops/generate_daily_research_todo.sh
  generated Docs/researches/todos_20260322.md (pending=1234, dirs=100, files=1134)
```

### 输出示例

```markdown
# Research TODOs 20260322

Project: `codex`
Generated at: 2026-03-22 15:44:03 +0800
Source: `Docs/researches/blueprint_checklist.md`

## Snapshot
- Done: 4500
- Pending: 399
- Pending Dirs: 50
- Pending Files: 349

## Pending Items
- [ ] [DIR] codex-rs/tui/src/components
- [ ] [FILE] codex-rs/tui/src/app.rs
...
```

## 依赖与外部交互

### 系统依赖

| 依赖 | 用途 | 必需 |
|------|------|------|
| `rg` (ripgrep) | 正则搜索 | 否（有降级） |
| `grep -E` | 降级正则搜索 | 是 |
| `wc` | 计数 | 是 |
| `tr` | 字符处理 | 是 |
| `date` | 日期生成 | 是 |
| `basename` | 提取项目名 | 是 |

### 外部工具链

脚本硬编码了 codex 和 node 的路径：

```bash
CODEX_VENDOR_PATH="/home/sansha/.nvm/versions/node/v24.14.0/lib/node_modules/@openai/codex/..."
export PATH="${CODEX_VENDOR_PATH}:/home/sansha/.nvm/versions/node/v24.14.0/bin:..."
```

**注意**：这些路径是特定于用户环境的，在其他机器上需要修改。

### 文件系统交互

```
读取:
  Docs/researches/blueprint_checklist.md

写入:
  Docs/researches/todos_YYYYMMDD.md

调用:
  .ops/generate_research_blueprint_checklist.sh (条件)
```

## 风险、边界与改进建议

### 风险点

#### 1. 硬编码路径

**问题**：脚本包含硬编码的 node 和 codex 路径，在其他环境无法运行。

```bash
# 当前实现
CODEX_VENDOR_PATH="/home/sansha/.nvm/versions/node/v24.14.0/..."
```

**影响**：脚本只能在特定用户环境执行。

#### 2. 日期边界问题

**问题**：脚本使用 `date +%Y%m%d` 生成文件名，跨天时可能产生歧义。

**示例**：
- 23:59 生成 `todos_20260322.md`
- 00:01 再次生成，覆盖或创建新文件

#### 3. 无历史累积

**问题**：每日 TODO 是独立文件，不保留历史趋势数据。

### 边界情况

| 场景 | 行为 |
|------|------|
| checklist 不存在 | 自动调用生成器创建 |
| checklist 为空 | 输出 `pending=0`，TODO 显示 "No pending research items" |
| 无 rg 命令 | 使用 grep -E 降级 |
| 目标目录不存在 | 依赖调用方创建 |
| 跨午夜执行 | 使用执行时的日期 |

### 改进建议

#### 1. 路径配置化

```bash
# 使用环境变量或配置文件
CODEX_VENDOR_PATH="${CODEX_VENDOR_PATH:-/home/sansha/.nvm/versions/node/v24.14.0/...}"
NVM_PATH="${NVM_PATH:-$HOME/.nvm/versions/node/v24.14.0/bin}"
```

#### 2. 支持增量更新

```bash
# 添加 --append 模式，追加而非覆盖
if [[ "${1:-}" == "--append" && -f "$TODO_FILE" ]]; then
  # 追加新发现的项目
else
  # 重新生成
fi
```

#### 3. 添加趋势统计

```bash
# 记录每日统计数据到 CSV
echo "$(date +%Y%m%d),$done_total,$pending_total,$dir_pending,$file_pending" \
  >> "$LOG_DIR/research_trend.csv"
```

#### 4. 优先级排序

```bash
# 按文件大小或目录深度排序待办项
rg '^-\ \[\ \]\ \[(DIR|FILE)\] ' "$CHECKLIST_FILE" | \
  while read line; do
    # 提取路径，计算优先级分数
  done | sort -k2 -n
```

#### 5. 添加进度百分比

```bash
# 计算完成百分比
total=$((done_total + pending_total))
if (( total > 0 )); then
  percent=$((done_total * 100 / total))
  echo "- Progress: ${percent}% (${done_total}/${total})"
fi
```

#### 6. 支持自定义输出格式

```bash
case "${OUTPUT_FORMAT:-markdown}" in
  markdown) generate_markdown ;;
  json) generate_json ;;
  csv) generate_csv ;;
esac
```

### 测试建议

1. **单元测试**：模拟不同 checklist 状态，验证统计准确性
2. **集成测试**：验证与 `generate_research_blueprint_checklist.sh` 的协作
3. **边界测试**：空 checklist、极大数字、特殊字符路径
