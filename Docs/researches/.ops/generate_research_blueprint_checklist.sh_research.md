# generate_research_blueprint_checklist.sh 研究文档

## 场景与职责

`generate_research_blueprint_checklist.sh` 是研究自动化系统的核心数据生成器，负责扫描整个代码仓库，生成包含所有目录和文件的完整研究清单（blueprint checklist）。它是整个研究 guard 系统的数据基础，决定了哪些项目需要被研究。

### 核心职责

1. **全仓库扫描**：递归扫描仓库中的所有目录和文件
2. **状态继承**：保留已有 checklist 中的完成状态标记
3. **清单生成**：生成格式统一的 Markdown checklist 文档
4. **排除管理**：智能排除不需要研究的目录（如 `.git`, `.cron` 等）

### 使用场景

- 初始化研究项目时生成初始清单
- 代码变更后更新清单（新增/删除文件）
- `research_guard.sh` 在每个任务完成后刷新清单
- 手动执行以同步仓库状态

## 功能点目的

### 1. 状态持久化

脚本使用关联数组 `STATUS` 保存已有 checklist 中的完成状态，确保刷新时不会丢失进度：

```bash
declare -A STATUS
if [[ -f "$CHECKLIST_FILE" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^-\ \[([xX\ ])\]\ \[(DIR|FILE)\]\ (.+)$ ]]; then
      mark="${BASH_REMATCH[1]}"
      kind="${BASH_REMATCH[2]}"
      path="${BASH_REMATCH[3]}"
      key="${kind}:${path}"
      if [[ "$mark" =~ [xX] ]]; then
        STATUS["$key"]="x"
      else
        STATUS["$key"]=" "
      fi
    fi
  done < "$CHECKLIST_FILE"
fi
```

### 2. 智能排除

使用 `find` 的 `-prune` 选项高效排除不需要研究的目录：

```bash
find . \
  \( -path './.git' -o -path './.git/*' \
     -o -path './Docs/researches' -o -path './Docs/researches/*' \
     -o -path './.cron' -o -path './.cron/*' \) -prune \
  -o -type d -print
```

排除项说明：
| 路径 | 排除原因 |
|------|----------|
| `.git/` | Git 元数据，非项目代码 |
| `Docs/researches/` | 研究生成的文档，避免递归研究 |
| `.cron/` | 运行时日志和状态文件 |

### 3. 规范化输出

- 使用 `sed 's|^\./||'` 移除 `./` 前缀
- 使用 `awk 'NF==0{print "."; next} {print}'` 处理空行为根目录 `.`
- 使用 `LC_ALL=C sort -u` 确保跨平台一致的排序

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 设置环境                                                  │
│    └─ PATH 和目录准备                                       │
├─────────────────────────────────────────────────────────────┤
│ 2. 读取已有状态                                              │
│    └─ 解析现有 checklist 到 STATUS 关联数组                 │
├─────────────────────────────────────────────────────────────┤
│ 3. 扫描目录                                                  │
│    └─ find + prune 排除不需要的路径                         │
├─────────────────────────────────────────────────────────────┤
│ 4. 扫描文件                                                  │
│    └─ 同样使用 find + prune                                 │
├─────────────────────────────────────────────────────────────┤
│ 5. 生成 checklist                                            │
│    └─ 合并目录和文件，应用状态标记                          │
├─────────────────────────────────────────────────────────────┤
│ 6. 输出统计                                                  │
│    └─ 打印生成摘要                                          │
└─────────────────────────────────────────────────────────────┘
```

### 关键数据结构

#### STATUS 关联数组

```bash
declare -A STATUS
# 键格式: "<TYPE>:<PATH>"
# 值: "x" (完成) 或 " " (待处理)

# 示例:
STATUS["DIR:codex-rs"]="x"
STATUS["FILE:README.md"]=" "
```

#### 正则解析模式

```bash
# 匹配 checklist 行
^-\ \[([xX\ ])\]\ \[(DIR|FILE)\]\ (.+)$

# 分组:
#   $1: 标记 ([ ], [x], [X])
#   $2: 类型 (DIR, FILE)
#   $3: 路径
```

### find 命令详解

#### 目录扫描

```bash
mapfile -t DIRS < <(
  find . \
    \( -path './.git' -o -path './.git/*' \
       -o -path './Docs/researches' -o -path './Docs/researches/*' \
       -o -path './.cron' -o -path './.cron/*' \) -prune \
    -o -type d -print \
  | sed 's|^\./||' \
  | awk 'NF==0{print "."; next} {print}' \
  | LC_ALL=C sort -u
)
```

- `-prune`：不进入匹配的目录
- `-o`（OR）：逻辑或
- `-type d`：只匹配目录
- `mapfile -t`：将输出读入数组，去除尾部换行

#### 文件扫描

与目录扫描类似，但使用 `-type f` 匹配文件。

### 输出生成

```bash
{
  echo "# Research Blueprint Checklist"
  echo
  echo "Project: \`$(basename "$REPO_ROOT")\`"
  echo "Generated at: $(date '+%F %T %z')"
  echo
  echo "Notes: excludes generated runtime paths \`.git/\`, \`.cron/\`, and \`Docs/researches/\`."
  echo "Legend: \`[ ]\` pending, \`[x]\` researched."
  echo
  echo "## Directories"
  for d in "${DIRS[@]}"; do
    key="DIR:${d}"
    mark="${STATUS[$key]:- }"  # 默认空格（待处理）
    echo "- [${mark}] [DIR] ${d}"
  done
  echo
  echo "## Files"
  for f in "${FILES[@]}"; do
    key="FILE:${f}"
    mark="${STATUS[$key]:- }"
    echo "- [${mark}] [FILE] ${f}"
  done
} > "$CHECKLIST_FILE"
```

## 关键代码路径与文件引用

### 本脚本位置

```
.ops/generate_research_blueprint_checklist.sh
```

### 输入文件

| 文件 | 路径 | 说明 |
|------|------|------|
| 已有 checklist | `Docs/researches/blueprint_checklist.md` | 可选，用于状态继承 |
| 仓库文件系统 | 整个仓库 | 扫描目标 |

### 输出文件

| 文件 | 路径 | 格式 |
|------|------|------|
| blueprint_checklist.md | `Docs/researches/blueprint_checklist.md` | Markdown checklist |

### 调用关系

```
调用方:
  research_guard.sh
    ├──> 启动时调用（refresh_checklist_with_lock）
    └──> 任务完成后调用（apply_success_updates_with_lock）
  
  generate_daily_research_todo.sh
    └──> checklist 不存在时调用

被调用:
  无
```

### 输出格式示例

```markdown
# Research Blueprint Checklist

Project: `codex`
Generated at: 2026-03-22 15:44:03 +0800

Notes: excludes generated runtime paths `.git/`, `.cron/`, and `Docs/researches/`.
Legend: `[ ]` pending, `[x]` researched.

## Directories
- [x] [DIR] .
- [x] [DIR] .codex
- [ ] [DIR] .codex/skills
...

## Files
- [x] [FILE] README.md
- [ ] [FILE] AGENTS.md
...
```

## 依赖与外部交互

### 系统依赖

| 依赖 | 用途 | 必需 |
|------|------|------|
| `find` | 文件系统扫描 | 是 |
| `sed` | 路径处理 | 是 |
| `awk` | 空行处理 | 是 |
| `sort` | 排序 | 是 |
| `rg` | 统计（可选） | 否 |
| `basename` | 提取项目名 | 是 |
| `date` | 时间戳 | 是 |
| `wc` | 计数 | 是 |
| `tr` | 字符处理 | 是 |

### Bash 特性

脚本依赖 Bash 4.0+ 的关联数组特性：

```bash
declare -A STATUS  # 关联数组
```

### 文件系统交互

```
读取:
  整个仓库目录结构
  Docs/researches/blueprint_checklist.md (可选)

写入:
  Docs/researches/blueprint_checklist.md
```

## 风险、边界与改进建议

### 风险点

#### 1. 符号链接处理

**问题**：`find` 默认会遍历符号链接，可能导致循环或重复。

**当前行为**：未处理，可能产生重复条目。

#### 2. 大仓库性能

**问题**：对于超大仓库（10万+ 文件），扫描可能很慢。

**影响**：阻塞研究 guard 的执行。

#### 3. 并发修改

**问题**：扫描和写入之间，文件系统可能变化。

**影响**：可能产生不一致的清单（已不存在的文件被标记为待处理）。

### 边界情况

| 场景 | 行为 |
|------|------|
| 空仓库 | 只生成根目录 `.` |
| 无权限目录 | find 报错到 stderr，跳过 |
| 特殊字符文件名 | 正常处理，包含在 checklist 中 |
| 破损的 checklist | 解析失败时，STATUS 为空，全部重置为待处理 |
| 极大文件数量 | 可能达到 shell 数组大小限制 |

### 改进建议

#### 1. 添加符号链接控制

```bash
# 添加 -type l 检查，或提供选项
find . -type l -print  # 列出所有符号链接

# 或跳过符号链接
find . -type l -prune -o ...
```

#### 2. 增量扫描

```bash
# 使用 mtime 只扫描变更的文件
find . -newer "$CHECKLIST_FILE" ...
```

#### 3. 性能优化

```bash
# 使用并行处理
find . ... -print0 | xargs -0 -P$(nproc) ...

# 或使用 fd 替代 find（更快）
if command -v fd >/dev/null 2>&1; then
  fd -t d .  # 目录
  fd -t f .  # 文件
fi
```

#### 4. 配置化排除

```bash
# 从配置文件读取排除模式
EXCLUDE_FILE="${REPO_ROOT}/.researchignore"
if [[ -f "$EXCLUDE_FILE" ]]; then
  while read pattern; do
    EXCLUDE_ARGS+=("-not" "-path" "$pattern")
  done < "$EXCLUDE_FILE"
fi
```

#### 5. 校验和验证

```bash
# 添加文件校验和，检测内容变化
generate_checksum() {
  find . -type f -exec sha256sum {} \; | sort
}
```

#### 6. 分层清单

```bash
# 按目录拆分清单，减少单文件大小
# 例如: blueprint_checklist_root.md, blueprint_checklist_codex-rs.md
```

#### 7. 添加元数据

```bash
# 在 checklist 头部添加更多元数据
echo "Total directories: ${#DIRS[@]}"
echo "Total files: ${#FILES[@]}"
echo "Last scan duration: ${duration}s"
```

### 测试建议

1. **功能测试**：验证扫描完整性，确保无遗漏
2. **状态继承测试**：修改 checklist 后重新生成，验证状态保留
3. **边界测试**：空目录、特殊字符、符号链接
4. **性能测试**：大仓库扫描时间基准
