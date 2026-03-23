# LICENSE.txt 研究文档

## 场景与职责

此文件是 **skill-installer** 技能的许可证文件，采用 **Apache License 2.0** 标准文本。作为系统预置技能（System Skill）的一部分，该许可证文件在构建时被嵌入到 Rust 二进制文件中，并在安装技能时随其他资源一起释放到用户目录。

### 在系统中的定位

- **文件路径**: `codex-rs/skills/src/assets/samples/skill-installer/LICENSE.txt`
- **所属技能**: `skill-installer`（技能安装器）
- **技能类型**: 系统预置技能（System Skill），位于 `.system` 命名空间
- **打包方式**: 通过 `include_dir` 宏在编译时嵌入到 `codex-skills` crate 中

## 功能点目的

### 1. 法律合规性

Apache License 2.0 是一种宽松的开源许可证，允许：
- 自由使用、修改和分发软件
- 商业用途
- 专利授权（明确的专利许可条款）
- 要求保留版权声明和许可文本

### 2. 技能分发的法律基础

该许可证为 skill-installer 技能提供了：
- **版权声明框架**: 用户必须保留原始版权声明
- **责任限制**: 明确声明软件按"原样"提供，不承担担保责任
- **贡献条款**: 明确了对项目贡献的许可条款

### 3. 与其他技能的许可证关系

根据 `SKILL.md` 中的说明：
- `.curated` 目录下的精选技能遵循各自的许可证
- `.experimental` 目录下的实验性技能同样遵循各自许可证
- `.system` 目录下的系统技能（包括 skill-installer）预装且通常采用 Apache 2.0

## 具体技术实现

### 嵌入机制

在 `codex-rs/skills/src/lib.rs` 中，整个 `samples` 目录通过以下方式嵌入：

```rust
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

这意味着 LICENSE.txt 的内容在编译时被读取并嵌入到最终二进制文件中。

### 指纹计算

系统技能安装时，会计算所有嵌入文件的指纹（包括 LICENSE.txt）：

```rust
fn collect_fingerprint_items(dir: &Dir<'_>, items: &mut Vec<(String, Option<u64>)>) {
    for entry in dir.entries() {
        match entry {
            include_dir::DirEntry::Dir(subdir) => { ... }
            include_dir::DirEntry::File(file) => {
                let mut file_hasher = DefaultHasher::new();
                file.contents().hash(&mut file_hasher);
                items.push((
                    file.path().to_string_lossy().to_string(),
                    Some(file_hasher.finish()),
                ));
            }
        }
    }
}
```

LICENSE.txt 的内容会被哈希计算，作为系统技能版本检测的一部分。

### 安装流程中的处理

当调用 `install_system_skills()` 函数时：

1. 检查目标目录 `$CODEX_HOME/skills/.system` 是否存在
2. 读取标记文件 `.codex-system-skills.marker` 对比指纹
3. 如果指纹不匹配或目录不存在：
   - 删除旧目录（如果存在）
   - 调用 `write_embedded_dir()` 将所有嵌入文件（包括 LICENSE.txt）写入磁盘
   - 写入新的标记文件

## 关键代码路径与文件引用

### 读取路径

| 阶段 | 代码位置 | 操作 |
|------|----------|------|
| 编译时 | `codex-rs/skills/src/lib.rs:12` | `include_dir!` 宏嵌入整个 samples 目录 |
| 构建时 | `codex-rs/skills/build.rs:5-11` | 监听 samples 目录变更，触发重新构建 |
| 运行时 | `codex-rs/skills/src/lib.rs:74` | `write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)` |
| 指纹计算 | `codex-rs/skills/src/lib.rs:87-99` | `embedded_system_skills_fingerprint()` 计算包含 LICENSE.txt 的指纹 |

### 写入路径

安装后，LICENSE.txt 被释放到：
```
$CODEX_HOME/skills/.system/skill-installer/LICENSE.txt
```

默认情况下 `$CODEX_HOME` 为 `~/.codex`。

### 相关测试

```rust
// codex-rs/skills/src/lib.rs:177-194
#[test]
fn fingerprint_traverses_nested_entries() {
    let mut items = Vec::new();
    collect_fingerprint_items(&SYSTEM_SKILLS_DIR, &mut items);
    // 验证嵌入目录结构完整性
}
```

## 依赖与外部交互

### 编译依赖

| 依赖 | 用途 |
|------|------|
| `include_dir` | 在编译时将目录内容嵌入二进制文件 |
| `codex-skills/build.rs` | 监听文件变更，确保构建时包含最新版本 |

### 运行时依赖

- 无直接运行时依赖
- 通过 `std::fs::write` 写入磁盘时依赖标准库文件系统操作

### 与其他组件的关系

```
codex-rs/skills/src/assets/samples/skill-installer/
├── LICENSE.txt          <-- 本文件（Apache 2.0 许可证）
├── SKILL.md             # 技能定义和使用文档
├── agents/openai.yaml   # OpenAI 接口配置
├── assets/              # 图标资源
└── scripts/             # Python 安装脚本
    ├── github_utils.py
    ├── install-skill-from-github.py
    └── list-skills.py
```

## 风险、边界与改进建议

### 潜在风险

1. **许可证冲突风险**
   - 如果 skill-installer 安装的第三方技能采用与 Apache 2.0 不兼容的许可证，可能产生合规问题
   - 建议：在 `install-skill-from-github.py` 中增加许可证兼容性检查

2. **许可证文本完整性**
   - 当前实现假设所有嵌入文件都能完整写入磁盘
   - 如果磁盘空间不足或权限问题，可能导致 LICENSE.txt 写入不完整
   - 建议：增加写入完整性校验

3. **指纹计算性能**
   - 每次启动都会计算所有系统技能文件的指纹（包括 LICENSE.txt）
   - 对于大量系统技能，这可能成为性能瓶颈
   - 建议：考虑增量更新或缓存机制

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 用户手动修改 `.system/skill-installer/LICENSE.txt` | 下次启动时指纹不匹配，整个 `.system` 目录被重置 | 符合设计，保护系统技能完整性 |
| 磁盘只读 | `install_system_skills` 返回 `SystemSkillsError::Io` | 需要上层处理错误 |
| `$CODEX_HOME` 未设置 | 默认使用 `~/.codex` | 符合预期 |

### 改进建议

1. **许可证元数据标准化**
   ```yaml
   # 建议在 agents/openai.yaml 中增加
   metadata:
     license: Apache-2.0
     license-file: LICENSE.txt
   ```

2. **安装时显示许可证**
   在 `install-skill-from-github.py` 中增加选项，允许用户在安装前查看技能许可证：
   ```python
   # 建议增加的功能
   parser.add_argument("--show-license", action="store_true", 
                       help="Display skill license before installation")
   ```

3. **许可证兼容性检查**
   对于从 GitHub 安装的技能，建议解析其 LICENSE 文件并检查与当前项目的兼容性。

4. **国际化支持**
   当前仅提供英文版 Apache 2.0 许可证。如果技能面向多语言用户，可考虑提供翻译版本（但法律文本仍以英文为准）。

### 安全考虑

- LICENSE.txt 作为纯文本文件，不存在代码执行风险
- 但需注意：如果攻击者能修改构建时的 LICENSE.txt，可能通过嵌入恶意内容（如超长文件导致 DoS）影响系统
- 建议：在 CI/CD 中验证嵌入文件的大小和格式
