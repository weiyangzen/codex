# uncrustify.sh 研究文档

## 场景与职责

`uncrustify.sh` 是 Bubblewrap 项目中用于批量格式化 C 源代码的 Shell 脚本。该脚本作为代码风格维护的便捷工具，确保所有 C 源文件和头文件遵循项目定义的代码风格规范。

### 核心职责

1. **批量格式化**：自动发现并格式化项目中所有 C 代码文件
2. **风格一致性**：使用 `uncrustify.cfg` 定义的统一风格
3. **简化操作**：将复杂的命令行封装为简单的脚本调用
4. **版本控制集成**：基于 Git 跟踪的文件列表进行操作

## 功能点目的

### 脚本功能

```bash
#!/bin/sh
uncrustify -c uncrustify.cfg --no-backup `git ls-tree --name-only -r HEAD | grep \\.[ch]$`
```

**分解说明**：

| 组件 | 功能 |
|------|------|
| `git ls-tree --name-only -r HEAD` | 列出 Git 仓库中所有跟踪的文件 |
| `grep \\.[ch]$` | 过滤出以 `.c` 或 `.h` 结尾的文件 |
| `uncrustify -c uncrustify.cfg` | 使用配置文件运行格式化工具 |
| `--no-backup` | 不创建备份文件（直接修改原文件） |

### 使用场景

1. **开发前准备**：
   ```bash
   # 修改代码前确保风格一致
   ./uncrustify.sh
   git commit -am "Apply code style"
   ```

2. **提交前检查**：
   ```bash
   # 提交前自动格式化
   ./uncrustify.sh
   git add -A
   git commit
   ```

3. **批量修复**：
   ```bash
   # 更新 uncrustify.cfg 后批量应用新风格
   ./uncrustify.sh
   git commit -am "Update code style to new rules"
   ```

## 具体技术实现

### 命令解析

#### 1. git ls-tree

```bash
git ls-tree --name-only -r HEAD
```

**参数说明**：
- `--name-only`：只输出文件名，不输出模式、类型、哈希
- `-r`：递归列出子目录中的文件
- `HEAD`：当前提交的树对象

**输出示例**：
```
bind-mount.c
bind-mount.h
bubblewrap.c
bwrap.xml
meson.build
network.c
network.h
uncrustify.cfg
uncrustify.sh
utils.c
utils.h
...
```

#### 2. grep 过滤

```bash
grep \\.[ch]$
```

**模式说明**：
- `\\.`：匹配字面量 `.`（在 shell 中需要转义）
- `[ch]`：匹配 `c` 或 `h`
- `$`：行尾锚点

**匹配结果**：
- `file.c` ✓
- `file.h` ✓
- `file.cc` ✗
- `file.cpp` ✗
- `README.md` ✗

#### 3. uncrustify 调用

```bash
uncrustify -c uncrustify.cfg --no-backup [文件列表...]
```

**参数说明**：
- `-c uncrustify.cfg`：指定配置文件
- `--no-backup`：不创建 `.uncrustify` 备份文件

**处理流程**：
1. 读取每个输入文件
2. 根据配置规则分析代码结构
3. 应用格式化规则
4. 直接覆盖原文件（因使用 `--no-backup`）

### 脚本特性

| 特性 | 说明 |
|------|------|
| Shell 兼容性 | 使用 `/bin/sh`，兼容 POSIX shell |
| 无参数设计 | 无需用户输入，一键执行 |
| Git 依赖 | 依赖 Git 获取文件列表 |
| 破坏性操作 | `--no-backup` 直接修改文件，需谨慎 |

## 关键代码路径与文件引用

### 依赖关系

```
uncrustify.sh
    ├── git ls-tree          # 获取文件列表
    ├── grep                 # 过滤 C 文件
    ├── uncrustify           # 格式化工具
    └── uncrustify.cfg       # 风格配置
```

### 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `uncrustify.cfg` | 配置文件 | 定义代码风格规则 |
| `*.c`, `*.h` | 目标文件 | 被格式化的源文件 |
| `.git/` | 数据源 | Git 仓库元数据 |

### 执行流程

```
执行 ./uncrustify.sh
       ↓
获取 Git 跟踪的所有文件
       ↓
过滤出 *.c 和 *.h 文件
       ↓
对每个文件调用 uncrustify
       ↓
直接修改原文件（无备份）
       ↓
完成
```

## 依赖与外部交互

### 运行时依赖

| 工具 | 用途 | 必需 |
|------|------|------|
| `/bin/sh` | 脚本解释器 | 是 |
| `git` | 获取文件列表 | 是 |
| `grep` | 过滤文件 | 是 |
| `uncrustify` | 格式化代码 | 是 |

### 安装依赖

```bash
# Debian/Ubuntu
sudo apt-get install uncrustify git

# Fedora
sudo dnf install uncrustify git

# Arch
sudo pacman -S uncrustify git

# macOS
brew install uncrustify git
```

### 环境要求

- 必须在 Git 仓库中执行（需要 `.git` 目录）
- 需要提交历史（`HEAD` 必须存在）
- 需要写权限（修改源文件）

## 风险、边界与改进建议

### 风险

1. **数据丢失风险**：
   - 风险：`--no-backup` 直接覆盖原文件
   - 场景：格式化可能引入意外变更
   - 缓解：执行前确保所有变更已提交

2. **未跟踪文件遗漏**：
   - 风险：`git ls-tree` 只处理已跟踪文件
   - 场景：新创建但未 `git add` 的文件不会被格式化
   - 缓解：先 `git add` 新文件再运行脚本

3. **工具版本差异**：
   - 风险：不同 Uncrustify 版本输出可能不同
   - 场景：团队成员使用不同版本
   - 缓解：指定版本要求

4. **Git 状态依赖**：
   - 风险：需要有效的 Git 仓库
   - 场景：从 tarball 解压的源码无法使用
   - 缓解：提供替代方案

### 边界

1. **仅处理 C 文件**：
   - 不处理 C++（.cpp, .cc, .hpp）
   - 不处理其他语言（Meson、Python、Shell）

2. **仅处理已跟踪文件**：
   - 忽略 `.gitignore` 的文件
   - 忽略未 `git add` 的新文件

3. **无交互性**：
   - 无法选择性格式化特定文件
   - 无法预览变更

4. **无错误处理**：
   - 脚本无错误检查
   - 任一命令失败不会停止

### 改进建议

1. **添加错误处理**：
   ```bash
   #!/bin/sh
   set -e  # 命令失败时退出
   
   if ! command -v uncrustify >/dev/null 2>&1; then
       echo "Error: uncrustify not found" >&2
       exit 1
   fi
   
   if ! git rev-parse --git-dir >/dev/null 2>&1; then
       echo "Error: not a git repository" >&2
       exit 1
   fi
   
   uncrustify -c uncrustify.cfg --no-backup $(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
   ```

2. **支持选择性格式化**：
   ```bash
   #!/bin/sh
   if [ $# -eq 0 ]; then
       # 无参数：格式化所有文件
       files=$(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
   else
       # 有参数：格式化指定文件
       files="$@"
   fi
   
   uncrustify -c uncrustify.cfg --no-backup $files
   ```

3. **添加预览模式**：
   ```bash
   #!/bin/sh
   if [ "$1" = "--check" ]; then
       # 检查模式：只显示差异
       for file in $(git ls-tree --name-only -r HEAD | grep '\.[ch]$'); do
           uncrustify -c uncrustify.cfg -p "$file" | diff -u "$file" -
       done
   else
       # 正常模式：直接格式化
       uncrustify -c uncrustify.cfg --no-backup $(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
   fi
   ```

4. **处理未跟踪文件**：
   ```bash
   #!/bin/sh
   # 包含已跟踪和已暂存的新文件
   files=$(git ls-tree --name-only -r HEAD; git diff --cached --name-only --diff-filter=A)
   echo "$files" | grep '\.[ch]$' | sort -u | xargs uncrustify -c uncrustify.cfg --no-backup
   ```

5. **添加备份选项**：
   ```bash
   #!/bin/sh
   if [ "$1" = "--backup" ]; then
       uncrustify -c uncrustify.cfg $(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
   else
       uncrustify -c uncrustify.cfg --no-backup $(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
   fi
   ```

6. **版本检查**：
   ```bash
   #!/bin/sh
   REQUIRED_VERSION="0.75"
   CURRENT_VERSION=$(uncrustify --version | grep -oE '[0-9]+\.[0-9]+')
   
   if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$CURRENT_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
       echo "Warning: uncrustify version $CURRENT_VERSION < $REQUIRED_VERSION" >&2
   fi
   
   uncrustify -c uncrustify.cfg --no-backup $(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
   ```

7. **CI 集成支持**：
   ```bash
   #!/bin/sh
   # 检查模式：用于 CI，失败如果有需要格式化的文件
   if [ "$1" = "--ci" ]; then
       TMPDIR=$(mktemp -d)
       cp -r . "$TMPDIR/original"
       uncrustify -c uncrustify.cfg --no-backup $(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
       if ! diff -r . "$TMPDIR/original" --exclude=.git >/dev/null 2>&1; then
           echo "Code style issues found. Run ./uncrustify.sh to fix." >&2
           rm -rf "$TMPDIR"
           exit 1
       fi
       rm -rf "$TMPDIR"
   else
       uncrustify -c uncrustify.cfg --no-backup $(git ls-tree --name-only -r HEAD | grep '\.[ch]$')
   fi
   ```
