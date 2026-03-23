# uncrustify.cfg 研究文档

## 场景与职责

`uncrustify.cfg` 是 Bubblewrap 项目的代码格式化工具 Uncrustify 的配置文件。该文件定义了项目的 C 代码风格规范，确保代码库中所有源代码文件遵循一致的格式。

### 核心职责

1. **代码风格标准化**：定义缩进、空格、换行等格式规则
2. **自动化格式化**：与 `uncrustify.sh` 脚本配合，批量格式化代码
3. **团队协作一致性**：确保所有贡献者遵循相同的代码风格
4. **减少风格争论**：通过工具自动化消除代码审查中的格式问题

## 功能点目的

### 1. 缩进规则（第 9-21 行）

```
indent_columns          2
indent_with_tabs        0
indent_align_string     True
indent_brace            2
indent_braces           false
indent_braces_no_func   True
indent_switch_case      0
indent_case_brace       2
indent_paren_close      1
```

**配置说明**：
- 使用 2 个空格缩进（非 Tab）
- 大括号单独一行，缩进 2 列
- switch 的 case 标签不额外缩进
- case 后的大括号缩进 2 列

**示例效果**：
```c
if (condition)
  {
    // 缩进 2 列
    do_something ();
  }

switch (value)
  {
  case 1:  // case 不缩进
    {
      // case 内大括号缩进 2 列
    }
    break;
  }
```

### 2. 空格规则（第 23-60 行）

**赋值和运算符**：
```
sp_assign                       Add
sp_arith                        Add
sp_bool                         Add
sp_compare                      Add
```

**函数调用**：
```
sp_func_def_paren               Force
sp_func_proto_paren             Force
sp_func_call_paren              Force
```

**效果**：强制在函数定义、声明和调用的参数列表前加空格
```c
// 强制格式
void function (int arg);

// 非强制格式（会被修正）
void function(int arg);
```

**指针和引用**：
```
sp_before_ptr_star              Add
sp_between_ptr_star             Remove
```

效果：
```c
char *ptr;      // * 前有空格
char **pptr;    // 两个 * 之间无空格
```

### 3. 换行规则（第 80-116 行）

**大括号换行**：
```
nl_if_brace                     Force
nl_brace_else                   Force
nl_for_brace                   Force
nl_while_brace                 Force
nl_switch_brace                Force
```

强制在控制结构后换行：
```c
// 强制格式
if (condition)
  {
  }

// 非强制格式（会被修正）
if (condition) {
}
```

**函数定义**：
```
nl_fdef_brace                   Force
nl_func_type_name               Force
```

强制函数定义的大括号换行：
```c
// 强制格式
static void
function_name (void)
  {
  }
```

### 4. 括号规则（第 119-127 行）

```
mod_full_brace_for              Remove
mod_full_brace_if               Remove
mod_full_brace_while            Remove
mod_full_brace_do               Remove
mod_full_brace_nl               3
```

**效果**：移除单语句块的多余大括号，但如果语句跨多行则保留：
```c
// 会被简化为
if (condition)
  do_something ();

// 但多行保留大括号
if (condition)
  {
    do_something ();
    do_more ();
  }
```

## 具体技术实现

### 配置格式

Uncrustify 使用自定义的配置文件格式：
- 每行一个配置项
- 格式：`key value`
- `#` 开头的行为注释
- 支持布尔值（true/false）、整数、枚举值

### 关键配置项分类

| 类别 | 配置项前缀 | 说明 |
|------|-----------|------|
| 缩进 | `indent_` | 控制代码缩进 |
| 空格 | `sp_` | 控制空格添加/删除 |
| 对齐 | `align_` | 控制代码对齐 |
| 换行 | `nl_` | 控制换行行为 |
| 修改 | `mod_` | 控制代码结构修改 |
| 位置 | `pos_` | 控制元素位置 |

### 与项目风格的匹配

Bubblewrap 项目采用类似 GNOME/Gtk 的 C 代码风格：
- 2 空格缩进
- 大括号单独一行
- 函数名后空格
- 紧凑的垂直间距

这与 Linux 内核风格（Tab 缩进、大括号同行）不同。

## 关键代码路径与文件引用

### 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `uncrustify.sh` | 调用方 | 使用此配置执行格式化 |
| `*.c`, `*.h` | 目标 | 被格式化的源文件 |

### uncrustify.sh 脚本

```bash
#!/bin/sh
uncrustify -c uncrustify.cfg --no-backup `git ls-tree --name-only -r HEAD | grep \\.[ch]$`
```

**功能**：
- 使用 `git ls-tree` 获取仓库中所有 C 源文件和头文件
- 调用 `uncrustify` 进行格式化
- `--no-backup`：不创建备份文件

### 使用流程

```
开发者修改代码
       ↓
运行 ./uncrustify.sh
       ↓
uncrustify 读取 uncrustify.cfg
       ↓
格式化所有 *.c 和 *.h 文件
       ↓
git diff 查看变更
       ↓
git add + git commit
```

## 依赖与外部交互

### 工具依赖

1. **Uncrustify**：
   - 代码格式化工具
   - 安装：`apt install uncrustify` 或从源码编译
   - 版本要求：建议使用最新版本

2. **Git**：
   - 用于获取文件列表
   - `git ls-tree` 命令

### 集成方式

**手动执行**：
```bash
./uncrustify.sh
```

**Git 钩子**（可选）：
```bash
# .git/hooks/pre-commit
#!/bin/sh
./uncrustify.sh
git add -A
```

**CI 检查**（建议）：
```yaml
# .github/workflows/style.yml
- name: Check code style
  run: |
    ./uncrustify.sh
    git diff --exit-code
```

## 风险、边界与改进建议

### 风险

1. **工具版本差异**：
   - 风险：不同 Uncrustify 版本可能产生不同输出
   - 缓解：指定版本要求，或在 CI 中使用固定版本

2. **配置与代码不匹配**：
   - 风险：配置更新后，大量代码需要重新格式化
   - 缓解：谨慎修改配置，批量格式化时单独提交

3. **意外修改**：
   - 风险：格式化可能引入意外变更（如宏处理）
   - 缓解：使用 `--no-backup` 前确保已提交代码

4. **遗漏文件**：
   - 风险：`git ls-tree` 只处理已跟踪文件
   - 缓解：新文件需要先 `git add`

### 边界

1. **仅支持 C/C++**：
   - 不适用于其他语言（如 Meson、Python、Shell）
   - 需要其他工具处理其他文件

2. **仅格式化语法**：
   - 不检查命名规范
   - 不检查代码逻辑
   - 不处理注释风格（除部分配置外）

3. **非项目标准**：
   - 与 Linux 内核风格不同
   - 与许多其他项目风格不同

### 改进建议

1. **版本锁定**：
   ```bash
   # uncrustify.sh
   REQUIRED_VERSION="0.75"
   CURRENT_VERSION=$(uncrustify --version | grep -oP '\d+\.\d+')
   ```

2. **选择性格式化**：
   ```bash
   # 只格式化修改的文件
   git diff --name-only HEAD | grep '\.[ch]$' | xargs uncrustify -c uncrustify.cfg --no-backup
   ```

3. **CI 集成**：
   ```yaml
   - name: Code style check
     run: |
       cp -r . /tmp/original
       ./uncrustify.sh
       diff -r . /tmp/original --exclude=.git
   ```

4. **配置验证**：
   ```bash
   # 验证配置有效性
   uncrustify -c uncrustify.cfg --show-config
   ```

5. **文档化风格**：
   - 除配置文件外，添加 CODING_STYLE.md 文档
   - 说明项目特定的风格决策

6. **编辑器集成**：
   - 提供 .editorconfig 文件
   - 提供常见编辑器的配置示例（Vim, Emacs, VS Code）

7. **增量格式化**：
   ```bash
   # 使用 pre-commit 框架
   # .pre-commit-config.yaml
   - repo: local
     hooks:
       - id: uncrustify
         name: uncrustify
         entry: uncrustify -c uncrustify.cfg --no-backup
         language: system
         files: '\.[ch]$'
   ```
