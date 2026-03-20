# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 上下文场景：`019_unicode_simple`

## 场景与职责

该目录是 `apply_patch` 场景测试 `019_unicode_simple` 的 expected 快照目录，当前仅含一个断言文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt:1-3`

其职责不是参与 patch 解析和执行，而是在场景测试收尾阶段提供“最终文件系统真值”：

1. `scenarios` runner 把 `input/` 复制到临时目录。
2. 调用 `apply_patch` 可执行文件执行 `patch.txt`。
3. 对比临时目录快照与 `expected/` 快照，二者必须完全一致。

关键依据：

- `codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`（准备输入目录）
- `codex-rs/apply-patch/tests/suite/scenarios.rs:40-48`（执行 patch）
- `codex-rs/apply-patch/tests/suite/scenarios.rs:51-58`（expected vs actual 深比较）
- `codex-rs/apply-patch/tests/suite/scenarios.rs:65-102`（目录快照数据结构 `Entry::File(Vec<u8>)`）

因此，`expected/` 本质是“验收标准文件集”，约束了 Unicode 文本替换后的最终字节内容。

## 功能点目的

该目录服务的功能点是：验证 **Unicode 文本行替换** 在端到端路径上的可观测结果正确。

围绕本场景的输入/补丁/期望三元组：

- 输入：`input/foo.txt` 第二行为 `naïve café`（`codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input/foo.txt:2`）
- 补丁：将 `-naïve café` 替换为 `+naïve café ✅`（`codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt:5-6`）
- 期望：`expected/foo.txt` 第二行为 `naïve café ✅`（`codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt:2`）

它验证的是“明确 Unicode 字面值替换成功”；并不直接验证 ASCII/Unicode 标点宽松匹配（该能力主要由 `seek_sequence` 与 `test_update_line_with_unicode_dash` 覆盖，见 `codex-rs/apply-patch/src/seek_sequence.rs:67-107`、`codex-rs/apply-patch/src/lib.rs:791-834`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 场景发现
- `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`，目录即测试单元（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。

2. patch 执行
- `run_apply_patch_scenario()` 读取 `patch.txt`，调用 `apply_patch` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:40-48`）。
- `apply_patch` CLI 入口在 `run_main()`，补丁参数必须是 UTF-8 字符串（`codex-rs/apply-patch/src/standalone_executable.rs:16-23`）。

3. 解析与应用
- `apply_patch()` 调 `parse_patch()`，再 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
- `parse_patch_text()` 把 patch 解析为 `Hunk` 序列（`codex-rs/apply-patch/src/parser.rs:154-183`）。
- `compute_replacements()` 计算替换区间，`apply_replacements()` 应用后写回文件（`codex-rs/apply-patch/src/lib.rs:386-474`、`codex-rs/apply-patch/src/lib.rs:478-501`、`codex-rs/apply-patch/src/lib.rs:327-329`）。

4. expected 断言
- `snapshot_dir()` 递归采样 expected 和实际目录，文件按 `Vec<u8>` 比较，确保字节级一致（`codex-rs/apply-patch/tests/suite/scenarios.rs:71-102`）。

### 2) 数据结构

- `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`：承载行替换信息（`codex-rs/apply-patch/src/parser.rs:90-104`）。
- `Hunk::UpdateFile`：描述更新目标路径与 chunks（`codex-rs/apply-patch/src/parser.rs:68-75`）。
- `Entry::File(Vec<u8>) | Dir`：场景对比结构，确保 expected 目录的断言粒度是“文件树 + 字节内容”（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`）。

### 3) 协议

- 场景协议（`input/` + `patch.txt` + `expected/`）定义见 `README.md`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。
- 文本行尾规则由 `.gitattributes` 限定为 LF（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`），减少跨平台换行噪音。
- `apply_patch` 语法说明见 `apply_patch_tool_instructions.md`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50`）。

### 4) 命令（研究与复现）

- 复现场景测试：
  - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
- 本次研究流程更新：
  - `bash .ops/generate_daily_research_todo.sh`（脚本逻辑见 `.ops/generate_daily_research_todo.sh:15-39`）

## 关键代码路径与文件引用

### 目标对象与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/expected/foo.txt:1-3`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/input/foo.txt:1-3`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/019_unicode_simple/patch.txt:1-7`

### 调用方（谁读取 expected）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:65-126`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`

### 被调用方（谁产生 actual）

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-339`
4. `codex-rs/apply-patch/src/lib.rs:348-552`
5. `codex-rs/apply-patch/src/parser.rs:106-183`
6. `codex-rs/apply-patch/src/parser.rs:246-333`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`
8. `codex-rs/apply-patch/src/invocation.rs:103-217`

### 配置、运行时与接入层上下文

1. `codex-rs/core/src/tools/spec.rs:321-380`（由 feature/model 决定 `apply_patch_tool_type`）
2. `codex-rs/core/src/tools/spec.rs:2784-2804`（注册 `apply_patch` tool spec 与 handler）
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`（patch 校验、审批、调度）
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构造 `codex --codex-run-as-apply-patch` 命令）
5. `codex-rs/core/src/config/mod.rs:528-531`（`include_apply_patch_tool` 配置项）
6. `codex-rs/core/src/features.rs:98-99`、`codex-rs/core/src/features.rs:639-643`（`ApplyPatchFreeform` feature）
7. `codex-rs/core/src/features/legacy.rs:25-31`、`codex-rs/core/src/features/legacy.rs:64-84`（legacy key 映射）
8. `codex-rs/arg0/src/lib.rs:13-14`、`codex-rs/arg0/src/lib.rs:85-107`（arg0 alias 和内部参数分发）

### 构建与文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:3-10`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. `.ops/generate_daily_research_todo.sh:1-42`
5. `Docs/researches/blueprint_checklist.md:140`

## 依赖与外部交互

### 依赖

`codex-apply-patch` 与本场景相关的核心依赖：

- `anyhow` / `thiserror`：错误建模与上下文。
- `similar`：在验证模式下生成 unified diff。
- `tree-sitter` / `tree-sitter-bash`：处理 shell/heredoc 形式调用解析。
- 测试依赖 `assert_cmd`、`tempfile`、`codex-utils-cargo-bin`、`pretty_assertions`。

来源：`codex-rs/apply-patch/Cargo.toml:18-30`。

### 外部交互

1. 文件系统交互
- 场景 runner 复制 `input/`、读取 `expected/`、读取文件字节做快照对比（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`、`:50-53`、`:99-101`）。
- `apply_patch` 执行时读取原文件并写回新文件（`codex-rs/apply-patch/src/lib.rs:352-359`、`:327-329`）。

2. 进程交互
- 测试中通过子进程调用 `apply_patch`（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
- Core runtime 中通过当前 `codex` 可执行 + `--codex-run-as-apply-patch` 间接执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:90-93`）。

3. 文本编码交互
- CLI 参数必须 UTF-8，非 UTF-8 直接报错退出（`codex-rs/apply-patch/src/standalone_executable.rs:20-22`）。
- 本场景的 `expected/foo.txt` 明确含多字节 UTF-8 字符（`ï`、`é`、`✅`），用于验证链路保真。

## 风险、边界与改进建议

### 风险

1. 覆盖面风险
- 当前 expected 仅单文件单行变化，无法覆盖多文件并发修改或目录级副作用。

2. 判定维度风险
- `scenarios` runner 不校验子进程退出码与 stderr，仅比较最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）；若出现“状态巧合一致但过程异常”，有漏检可能。

3. 编码前提风险
- `apply_patch` 明确依赖 UTF-8 输入；非 UTF-8 工作流不在该场景保障范围内。

### 边界

1. 本目录只表达“最终状态应是什么”，不包含“为什么失败”的错误语义断言。
2. 不覆盖 Unicode 正规化差异（NFC/NFD）或跨平台编码变体。
3. 不覆盖 ASCII patch 与 Unicode 标点源码之间的模糊匹配能力（这是 `seek_sequence` + 单测关注点）。

### 改进建议

1. 增补 `scenarios` 元数据断言（如 `expected_exit_code`、`stderr_contains`），让 expected 目录与执行语义形成双重保障。
2. 为 Unicode 场景增加矩阵：
- 多文件替换
- NFC/NFD 等价字符
- 包含非断行空格（NBSP）

3. 增加一个与 `expected/` 对应的“字节签名说明”（或自动校验脚本），在 review 阶段更直观看到 UTF-8 多字节变化，降低肉眼漏看风险。
