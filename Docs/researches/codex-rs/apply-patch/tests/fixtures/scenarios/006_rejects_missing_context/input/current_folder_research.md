# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `006_rejects_missing_context` 的输入快照目录，承担“失败前原始文件状态基线”的职责。

目录内仅有一个文件：

1. `modify.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input/modify.txt:1-2`），内容为：
   - `line1`
   - `line2`

同场景补丁为：

- `patch.txt` 将 `-missing` 替换为 `+changed`（`codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/patch.txt:1-6`）。

因为输入文件并不包含 `missing`，该场景应触发“上下文缺失拒绝”。因此 `input/` 的职责不是触发成功修改，而是作为“失败后不应被改写”的初始态锚点，与 `expected/modify.txt` 形成等值对照（`.../expected/modify.txt:1-2`）。

## 功能点目的

该目录服务的是 `Update File` 语义里最关键的安全约束：`old_lines` 必须可定位，否则补丁失败。

1. 防止误改：禁止在未命中旧行时进行近似替换。
2. 保证可解释失败：输出 `Failed to find expected lines in modify.txt:\nmissing`（`codex-rs/apply-patch/src/lib.rs:464`，`codex-rs/apply-patch/tests/suite/tool.rs:107`）。
3. 保证失败无副作用：输入文件在失败后保持 `line1\nline2\n`（`codex-rs/apply-patch/tests/suite/tool.rs:98-109`，`codex-rs/core/tests/suite/apply_patch_cli.rs:404-429`）。
4. 提供可移植 fixture：场景规范要求每个测试用例以 `input/ + patch.txt + expected/` 组织（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 场景回放入口 `test_apply_patch_scenarios()` 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 将本目录 `input/` 递归复制到临时目录（`scenarios.rs:30-37,107-123`）。
3. 读取同级 `patch.txt`，执行 `apply_patch <patch>`（`scenarios.rs:39-48`）。
4. 场景测试故意不检查退出码，仅比较最终文件树快照（`scenarios.rs:42-45,50-60`）。
5. 快照结构为 `BTreeMap<PathBuf, Entry>`，`Entry = File(Vec<u8>) | Dir`（`scenarios.rs:65-77`），因此会对 `modify.txt` 做字节级等值比较。

### 2) 解析与应用链路（为何本目录内容不变）

1. `parse_patch()` 解析 `*** Update File: modify.txt` + `@@` + `-missing/+changed` 为 `Hunk::UpdateFile`（`codex-rs/apply-patch/src/parser.rs:106-113,279-333,343-434`）。
2. `apply_patch()` -> `apply_hunks()` -> `apply_hunks_to_files()`（`codex-rs/apply-patch/src/lib.rs:183-266,279-339`）。
3. `derive_new_contents_from_chunks()` 读取目标文件并拆行为 `Vec<String>`（`lib.rs:348-381`）。
4. `compute_replacements()` 通过 `seek_sequence()` 在输入行中查找 chunk 的 `old_lines=["missing"]`（`lib.rs:386-474`）。
5. 查找失败时返回 `ApplyPatchError::ComputeReplacements("Failed to find expected lines in ...")`（`lib.rs:463-467`），因此不会进入写回分支，输入文件保持不变。

### 3) 匹配算法细节

`seek_sequence()` 的匹配顺序（`codex-rs/apply-patch/src/seek_sequence.rs:12-110`）：

1. 精确匹配。
2. 忽略行尾空白匹配（`trim_end`）。
3. 忽略两侧空白匹配（`trim`）。
4. Unicode 标点归一化匹配（`normalise`）。

本目录 `modify.txt` 的两行文本与 `missing` 在四轮匹配均不命中，所以稳定拒绝。

### 4) 协议与命令

1. 补丁协议 grammar（freeform）：`start: begin_patch hunk+ end_patch`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-17`）。
2. 说明文档：`apply_patch_tool_instructions.md`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-76`）。
3. CLI 入口：`run_main()` 支持 argv 或 stdin（`codex-rs/apply-patch/src/standalone_executable.rs:11-52`）。
4. 本场景等价命令：

```bash
apply_patch "*** Begin Patch
*** Update File: modify.txt
@@
-missing
+changed
*** End Patch"
```

## 关键代码路径与文件引用

### 目标目录与直接对象

1. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/input/modify.txt:1-2`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/patch.txt:1-6`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/006_rejects_missing_context/expected/modify.txt:1-2`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`（LF 结尾约束）
5. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`

### 调用方（谁消费该 input）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`（场景遍历）
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-37`（复制 input）
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`（最终状态断言）
4. `codex-rs/apply-patch/tests/all.rs:1-3`（集成测试聚合入口）

### 被调用方（执行时进入的实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-52`
2. `codex-rs/apply-patch/src/lib.rs:183-266`（apply_patch/apply_hunks）
3. `codex-rs/apply-patch/src/lib.rs:279-339`（hunk 执行）
4. `codex-rs/apply-patch/src/lib.rs:348-474`（读取、定位、失败诊断）
5. `codex-rs/apply-patch/src/parser.rs:343-434`（update chunk 解析）
6. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`（上下文查找）

### 配置、测试、脚本、文档链路

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与依赖）
2. `codex-rs/apply-patch/BUILD.bazel:1-11`（`compile_data` 暴露协议文档）
3. `codex-rs/apply-patch/tests/suite/tool.rs:98-109`（missing context CLI 断言）
4. `codex-rs/core/tests/suite/apply_patch_cli.rs:404-429`（core 端到端 missing context 断言）
5. `codex-rs/core/src/tools/handlers/apply_patch.rs:174-243,272-347`（`maybe_parse_apply_patch_verified` 与 `apply_patch verification failed`）
6. `codex-rs/core/src/tools/spec.rs:263,370-379,2784-2804`（`apply_patch_tool_type` 配置与注册）
7. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-96`（构建 `--codex-run-as-apply-patch` 命令）
8. `codex-rs/arg0/src/lib.rs:90-106`（argv1 分发到 `codex_apply_patch::apply_patch`）
9. `.ops/generate_daily_research_todo.sh:5-7,15-18,37-39`（研究 todo 生成脚本）
10. `Docs/researches/blueprint_checklist.md:95`（本次勾选项）

## 依赖与外部交互

### 依赖

1. 运行时依赖：`anyhow`、`thiserror`、`similar`（`codex-rs/apply-patch/Cargo.toml`）。
2. 解析相关：`tree-sitter`、`tree-sitter-bash`（主要用于 invocation 路径，见 `codex-rs/apply-patch/src/invocation.rs:103-206`）。
3. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`Cargo.toml` dev-dependencies）。

### 外部交互

1. 文件系统：场景 runner 复制 `input/`，apply_patch 读取/尝试写回目标文件，快照器读取字节内容。
2. 子进程：测试通过 `Command::new(cargo_bin("apply_patch"))` 启动工具进程（`scenarios.rs:45-48`）。
3. 标准流：错误经 stderr 输出，在 `tool.rs`/`core` 测试断言。
4. 跨 crate 协作：core handler 先做 verified parse，再转运行时执行；运行时通过 arg0 secret argv1 回到 apply-patch crate 执行。

## 风险、边界与改进建议

### 风险

1. `scenarios.rs` 不断言退出码与 stderr，仅校验最终文件树；若报错文案退化，该层可能无法发现（`scenarios.rs:42-45`）。
2. apply_patch 非事务化；多 hunk/多文件 patch 可能出现“前半成功后半失败仍保留部分写入”（`codex-rs/apply-patch/tests/suite/tool.rs:243-257`）。
3. 本目录只有单文件两行输入，覆盖面偏窄，不能单独暴露复杂上下文冲突。

### 边界

1. `@@` 可为空上下文，但 `old_lines` 仍必须可查找；本场景验证“无上下文锚 + 删除行不存在”的硬失败路径。
2. `seek_sequence()` 允许空白与 Unicode 归一化容错；本场景属于“即使最宽松也无法匹配”的边界。
3. 行尾规则由 `.gitattributes` 限定为 LF，避免跨平台 CRLF 干扰 fixture 稳定性。

### 改进建议

1. 为场景框架增加可选元数据（`expected_exit_code`、`stderr_contains`），让负向 fixture 同时验证副作用与错误诊断。
2. 为 `006` 补充变体：`missing` 仅空白差异/大小写差异/Unicode 归一化差异，明确容错边界。
3. 在 `test_apply_patch_scenarios()` 中对目录名排序后执行，提升 CI 失败复现稳定性。
