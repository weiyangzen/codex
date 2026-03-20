# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`021_update_file_deletion_only`

## 场景与职责

该目录是场景 `021_update_file_deletion_only` 的 expected 结果集，当前只包含一个断言文件：

- `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected/lines.txt:1`

它的职责不是触发 patch 执行，而是作为“最终真值（oracle）”参与目录快照比对，定义该场景执行后应得到的文件系统状态：

1. `lines.txt` 仍然存在（说明是 `Update File` 修改，不是 `Delete File` 删除文件）。
2. 文件内容应由三行变两行：从 `line1\nline2\nline3\n` 变为 `line1\nline3\n`，即只删除中间行。
3. 该结果目录用于约束“仅删除行（deletion-only update chunk）”语义是否稳定。

在场景矩阵里的定位：

1. 与 `020_delete_file_success` 的“整文件删除”互补：`020` 验证 `Delete File`，`021` 验证 `Update File` 的行级删除。
2. 与 `016_pure_addition_update_chunk` 的“仅新增”互补：`016` 和 `021` 一起覆盖单侧变更（only-add / only-delete）。
3. 与 `022_update_file_end_of_file_marker` 区分：`022` 强调 `*** End of File` 锚点，`021` 强调普通上下文删除。

## 功能点目的

该 expected 目录保护的核心功能点是：**在 `Update File` hunk 中，仅使用 `-` 删除线也必须正确更新文件并保留上下文行**。

对应约束目标：

1. parser 能正确解析删除型 hunk：`-line2` 进入 `old_lines`，上下文 ` line1`/` line3` 同时进入 `old_lines` 与 `new_lines`。
2. 执行器能把“old 比 new 长”的 replacement 正确应用到目标文件，最终删除指定行。
3. 目录级断言要求最终文件树和字节内容与 expected 完全一致，避免出现“内容正确但文件结构错误”或“行尾处理不一致”。
4. 回归时可快速定位问题归属：
   - 解析问题（`parser.rs`）
   - 匹配/替换问题（`seek_sequence.rs` + `lib.rs`）
   - 场景框架问题（`tests/suite/scenarios.rs`）

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与场景组成

`scenarios` 目录遵循统一协议：每个场景由 `input/` + `patch.txt` + `expected/` 三部分组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`-`7`）。

本场景资产：

1. `patch.txt`：
   - `*** Update File: lines.txt`
   - hunk 中保留 `line1`、删除 `line2`、保留 `line3`
   - 见 `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/patch.txt:1`-`7`
2. `input/lines.txt`：三行原始内容（`.../input/lines.txt:1`-`3`）。
3. `expected/lines.txt`：两行目标内容（`.../expected/lines.txt:1`-`2`）。

### 2) 调用链（调用方 -> 被调用方）

场景执行链路：

1. `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*` 目录并执行每个场景（`codex-rs/apply-patch/tests/suite/scenarios.rs:11`-`23`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到临时目录，读取 `patch.txt` 并调用 `apply_patch` 二进制（`.../scenarios.rs:30`-`48`）。
3. 最终通过 `snapshot_dir(expected)` 与 `snapshot_dir(actual)` 进行字节级目录快照比较（`.../scenarios.rs:51`-`58`，`71`-`103`）。
4. 本目录即 `expected` 端的断言输入，任何差异都会触发 `assert_eq!` 失败。

### 3) patch 解析与删除语义落点

解析入口是 `parse_patch()`（`codex-rs/apply-patch/src/parser.rs:106`），本场景命中 `Hunk::UpdateFile`：

1. `parse_one_hunk()` 识别 `*** Update File: lines.txt`（`parser.rs:279`-`333`）。
2. `parse_update_file_chunk()` 处理 hunk 行（`parser.rs:343`-`434`）：
   - 空格前缀行 ` line1` / ` line3`：同时压入 `old_lines` 与 `new_lines`（`405`-`408`）。
   - `-line2`：仅压入 `old_lines`（`412`-`414`）。
3. 结果是一个“删除型 replacement 模式”：`old_lines` 包含三行，`new_lines` 仅两行。

可抽象为：

```text
old_lines = ["line1", "line2", "line3"]
new_lines = ["line1", "line3"]
```

### 4) 文件更新算法（匹配、替换、行尾）

执行入口 `apply_patch()` -> `apply_hunks()` -> `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183`-`210`，`216`-`339`）。

针对 `UpdateFile`：

1. `derive_new_contents_from_chunks()` 读取原文件并按 `\n` 切分为行数组（`lib.rs:348`-`363`）。
2. 为贴近 `diff` 语义，会移除尾随空元素（`364`-`368`）。
3. `compute_replacements()` 调用 `seek_sequence()` 在原文件中定位 `old_lines`，生成 replacement（三元组：起始行、旧长度、新片段）（`386`-`474`）。
4. `apply_replacements()` 按倒序执行删除和插入（`478`-`501`），本场景属于“删 3 行插 2 行”。
5. 若结果末尾无空行，会补一个空行并 `join("\n")`，确保最终文件保留结尾换行（`373`-`376`）。

`seek_sequence()` 的容错匹配顺序：精确匹配 -> 忽略尾空白 -> 忽略首尾空白 -> Unicode 标点归一化（`codex-rs/apply-patch/src/seek_sequence.rs:1`-`109`）。这使 deletion-only 场景在轻微空白差异下仍可定位。

### 5) 上下文依赖：core/配置/审批执行链

尽管本 fixture 测试直接跑 `apply_patch` 二进制，生产链路还会经过 core 的验证与审批：

1. 配置层由 `include_apply_patch_tool` 控制是否启用该工具（`codex-rs/core/src/config/mod.rs:528`-`531`）。
2. 工具注册层在 `spec` 中根据 `apply_patch_tool_type` 注入 freeform/function 版本并绑定 handler（`codex-rs/core/src/tools/spec.rs:2784`-`2804`）。
3. handler 会先 `maybe_parse_apply_patch_verified()` 做结构化验证，再进入审批与 runtime（`codex-rs/core/src/tools/handlers/apply_patch.rs:170`-`257`，`262`-`356`）。
4. runtime 通过 `codex --codex-run-as-apply-patch <patch>` 执行真实写盘（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69`-`95`）。
5. `arg0` 分发层接收 `--codex-run-as-apply-patch` 并调用 `codex_apply_patch::apply_patch()`（`codex-rs/arg0/src/lib.rs:90`-`107`）。

这说明 expected 目录虽然是测试资产，但其正确性直接关联到线上工具调用、审批展示与实际文件写入路径。

### 6) 关键命令（研究/验证/维护）

1. 仅跑场景集：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 跑 apply-patch crate 全测：
   - `cargo test -p codex-apply-patch`
3. 更新每日 research todo（本任务要求）：
   - `bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 研究对象与直接场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/expected/lines.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/input/lines.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/021_update_file_deletion_only/patch.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5`

### B. 直接调用方（fixture runner）

1. `codex-rs/apply-patch/tests/all.rs:1`
2. `codex-rs/apply-patch/tests/suite/mod.rs:2`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:30`
5. `codex-rs/apply-patch/tests/suite/scenarios.rs:51`

### C. 被调用方（parser / apply engine）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11`
2. `codex-rs/apply-patch/src/lib.rs:183`
3. `codex-rs/apply-patch/src/lib.rs:279`
4. `codex-rs/apply-patch/src/lib.rs:306`
5. `codex-rs/apply-patch/src/lib.rs:348`
6. `codex-rs/apply-patch/src/lib.rs:386`
7. `codex-rs/apply-patch/src/lib.rs:478`
8. `codex-rs/apply-patch/src/parser.rs:279`
9. `codex-rs/apply-patch/src/parser.rs:343`
10. `codex-rs/apply-patch/src/seek_sequence.rs:12`

### D. 上下文依赖（配置/工具注册/runtime/分发）

1. `codex-rs/core/src/config/mod.rs:528`
2. `codex-rs/core/src/tools/spec.rs:2784`
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:262`
4. `codex-rs/apply-patch/src/invocation.rs:132`
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69`
6. `codex-rs/arg0/src/lib.rs:90`

### E. 测试、脚本、文档与构建

1. `codex-rs/apply-patch/tests/suite/tool.rs:98`（缺失上下文失败示例）
2. `codex-rs/core/tests/suite/apply_patch_cli.rs:143`（多 chunk 更新）
3. `codex-rs/core/tests/suite/apply_patch_cli.rs:1071`（EOF 锚点更新）
4. `codex-rs/apply-patch/Cargo.toml:1`
5. `codex-rs/apply-patch/BUILD.bazel:5`
6. `codex-rs/apply-patch/apply_patch_tool_instructions.md:43`
7. `.ops/generate_daily_research_todo.sh:5`
8. `Docs/researches/blueprint_checklist.md:149`

## 依赖与外部交互

### 1) crate 与测试依赖

`codex-apply-patch` 关键依赖（`codex-rs/apply-patch/Cargo.toml:18`-`30`）：

1. `anyhow` / `thiserror`：错误建模和上下文。
2. `similar`：在 verified 路径生成 unified diff（用于审批展示和协议输出）。
3. `tree-sitter` / `tree-sitter-bash`：shell heredoc 形式 `apply_patch` 识别。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：集成测试框架。

### 2) 文件系统与进程交互

1. 场景 runner 会复制输入目录、启动子进程执行 `apply_patch`、再读取目录快照对比（`tests/suite/scenarios.rs:34`-`48`，`71`-`103`）。
2. `Update File` 写盘路径为“读原文件 -> 计算新内容 -> 覆盖写回”（`lib.rs:352`-`377`，`327`-`329`）。
3. 场景文件受 `** text eol=lf` 约束，减少跨平台换行噪声（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

### 3) 与 core 的外部交互

1. core handler 对 patch 做 verified 解析，输出结构化文件改动，用于审批和事件流（`core/src/tools/handlers/apply_patch.rs:170`-`237`）。
2. runtime 构造最小环境命令规范并在沙箱策略下执行（`core/src/tools/runtimes/apply_patch.rs:69`-`107`，`196`-`213`）。
3. `arg0` 机制保证 `apply_patch` 可通过别名/内部参数分发到同一实现（`arg0/src/lib.rs:85`-`107`，`214`-`223`）。

## 风险、边界与改进建议

### 风险

1. `scenarios` 框架故意不检查进程退出码与 stderr，仅比较最终文件树；若“执行过程异常但最终态偶然一致”，可能漏报（`tests/suite/scenarios.rs:42`-`48`）。
2. 本 expected 仅覆盖单文件、单删除块、唯一上下文，无法覆盖重复片段歧义（如文件中多处 `line1 line2 line3`）。
3. 删除型 chunk 对 `seek_sequence` 容错策略敏感，若后续放宽/收紧匹配规则，可能引入误匹配或匹配失败回归。

### 边界

1. 本目录不覆盖失败路径（缺文件、目录删除、权限失败）；这些由其他场景和 `tool.rs`/core suite 覆盖。
2. 不覆盖 rename（`*** Move to`）、多文件原子性、审批交互；这里只定义最终文件内容断言。
3. 不覆盖 `*** End of File` 语义（该边界由 `022_update_file_end_of_file_marker` 场景覆盖）。

### 改进建议

1. 为 `scenarios` 增加可选元数据（例如 `exit_code` / `stderr_contains`），在保持最终态断言的同时提升可观测性。
2. 新增 deletion-only 变体场景：
   - 重复上下文块（验证定位是否唯一）
   - 多段删除（同文件多 chunk）
   - 首行/尾行删除（与 EOF 行为组合）
3. 在 `scenarios/README.md` 增加“单侧更新矩阵（only-add/only-delete/eof-anchor）”索引，便于维护者快速定位覆盖空洞。
4. 在 core `apply_patch_cli` 套件增加 deletion-only 明确用例，与 fixture 场景一一对照，减少“fixture 覆盖有、核心套件同类断言缺失”的认知断层。
