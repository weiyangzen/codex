# license.txt 研究文档

## 场景与职责

`license.txt` 是 `skill-creator` 系统技能的许可证文件，采用 **Apache License 2.0** 标准文本。

### 核心职责

1. **法律合规**: 明确技能代码和文档的使用、修改、分发条款
2. **版权保护**: 定义版权归属和衍生作品规则
3. **专利授权**: 提供明确的专利使用授权和终止条款
4. **免责声明**: 限定责任范围，保护贡献者

### 在项目中的定位

- 该文件位于 `codex-rs/skills/src/assets/samples/skill-creator/`
- 作为系统技能的一部分，随技能内容一起被嵌入和分发
- 适用于 skill-creator 目录下的所有脚本（Python）和文档内容

---

## 功能点目的

### 1. 定义许可证条款

**关键条款概览**：

| 条款 | 内容 | 目的 |
|------|------|------|
| **第 1 条 - 定义** | 定义 License、Licensor、Work、Contribution 等术语 | 消除歧义，明确适用范围 |
| **第 2 条 - 版权授权** | 授予复制、修改、分发、再许可的永久权利 | 确保开源自由度 |
| **第 3 条 - 专利授权** | 授予必要专利权利，诉讼时终止 | 保护用户免受专利诉讼 |
| **第 4 条 - 再分发条件** | 保留版权声明、提供许可证副本、标注修改 | 维护归属链条 |
| **第 5 条 - 贡献条款** | 提交贡献即视为接受许可证 | 简化贡献流程 |
| **第 6 条 - 商标** | 不授予商标使用权 | 保护品牌 |
| **第 7-9 条** | 免责声明、责任限制、额外担保 | 法律保护 |

### 2. 提供应用指南

附录部分包含将 Apache License 应用到其他作品的模板：

```
Copyright [yyyy] [name of copyright owner]

Licensed under the Apache License, Version 2.0...
```

### 3. 与项目整体许可证的关系

- 项目根目录的 `LICENSE` 文件也是 Apache 2.0
- 本文件与根许可证一致，确保整个项目许可证统一
- 系统技能作为项目的一部分，遵循相同许可证策略

---

## 具体技术实现

### 文件格式

- **格式**: 纯文本（ASCII）
- **大小**: 11,358 bytes
- **行数**: 202 行
- **编码**: UTF-8 兼容

### 标准结构

```
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

1. Definitions.
   ...
   
2. Grant of Copyright License.
   ...

[条款 3-9]

END OF TERMS AND CONDITIONS

APPENDIX: How to apply the Apache License to your work.
   ...
```

### 关键法律文本

**版权授权**（第 2 条）：
```
perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable
copyright license to reproduce, prepare Derivative Works of,
publicly display, publicly perform, sublicense, and distribute the
Work and such Derivative Works in Source or Object form.
```

**专利授权**（第 3 条）：
```
perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable
(except as stated in this section) patent license...
```

**专利终止条款**（第 3 条）：
```
If You institute patent litigation against any entity... alleging that 
the Work or a Contribution incorporated within the Work constitutes 
direct or contributory patent infringement, then any patent licenses 
granted to You under this License for that Work shall terminate...
```

**再分发条件**（第 4 条）：
- (a) 提供许可证副本
- (b) 标注修改的文件
- (c) 保留所有归属声明
- (d) 如有 NOTICE 文件，需包含其内容

---

## 关键代码路径与文件引用

### 当前文件

- **路径**: `codex-rs/skills/src/assets/samples/skill-creator/license.txt`
- **大小**: 11,358 bytes
- **行数**: 202 行

### 同目录相关文件

| 文件 | 路径 | 关系 |
|------|------|------|
| `SKILL.md` | `SKILL.md` | 主文档，受本许可证保护 |
| `init_skill.py` | `scripts/init_skill.py` | 脚本，受本许可证保护 |
| `generate_openai_yaml.py` | `scripts/generate_openai_yaml.py` | 脚本，受本许可证保护 |
| `quick_validate.py` | `scripts/quick_validate.py` | 脚本，受本许可证保护 |
| `openai_yaml.md` | `references/openai_yaml.md` | 参考文档，受本许可证保护 |
| `openai.yaml` | `agents/openai.yaml` | UI 元数据，受本许可证保护 |

### 项目级许可证文件

| 文件 | 路径 | 说明 |
|------|------|------|
| `LICENSE` | `/home/sansha/Github/codex/LICENSE` | 项目根许可证（Apache 2.0） |
| `NOTICE` | `/home/sansha/Github/codex/NOTICE` | 项目归属声明 |

### 调用方代码

该文件通过以下路径被嵌入和分发：

```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
// 整个目录（包含 license.txt）被嵌入
```

---

## 依赖与外部交互

### 法律依赖

| 依赖 | 说明 |
|------|------|
| Apache License 2.0 标准文本 | 官方模板，未经修改 |
| 美国版权法 | 许可证的法律基础 |
| 专利法 | 第 3 条专利授权的法律基础 |

### 分发机制

- **编译时**: 通过 `include_dir` crate 嵌入到 `codex-skills` crate
- **运行时**: 通过 `install_system_skills()` 解压到用户目录
- **最终位置**: `CODEX_HOME/skills/.system/skill-creator/license.txt`

### 与其他系统技能的关系

| 技能 | 许可证情况 |
|------|------------|
| `skill-creator` | Apache 2.0（本文件） |
| `skill-installer` | Apache 2.0（项目统一） |
| `openai-docs` | 需单独确认（可能包含第三方内容） |

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 许可证冲突 | 用户可能将 skill-creator 代码与不兼容许可证的代码混合 | Apache 2.0 与大多数开源许可证兼容 |
| 归属缺失 | 再分发时可能遗漏许可证副本 | 验证脚本不检查许可证文件存在性 |
| 专利诉讼 | 第 3 条的专利终止条款可能吓退企业用户 | 标准 Apache 2.0 条款，业界广泛接受 |

### 边界情况

1. **文件缺失**: 如果 `license.txt` 被意外删除，技能内容仍然受项目根 `LICENSE` 保护
2. **修改检测**: 当前无机制验证许可证文件是否被篡改
3. **国际适用性**: Apache 2.0 基于美国法律，在某些司法管辖区可能需要额外考虑

### 改进建议

#### 高优先级

1. **添加版权声明**
   - 当前文件使用模板形式的 `[yyyy] [name of copyright owner]`
   - 建议添加具体的版权声明文件或更新为实际版权信息
   - 可在 `NOTICE` 文件中添加 skill-creator 的归属声明

2. **验证脚本增强**
   - `quick_validate.py` 应检查许可证文件存在性
   - 可添加许可证类型验证（确保是 Apache 2.0）

#### 中优先级

3. **许可证头部注释**
   - Python 脚本文件（`init_skill.py` 等）建议添加许可证头部注释
   - 符合 Apache 2.0 的最佳实践

   示例：
   ```python
   # Copyright 2024 OpenAI
   # SPDX-License-Identifier: Apache-2.0
   ```

4. **SPDX 标识符**
   - 在 `SKILL.md` frontmatter 中添加 `license: Apache-2.0`
   - 便于自动化工具识别

#### 低优先级

5. **多语言许可证**
   - 考虑提供非英语翻译版本（仅供参考，法律上仍以英文为准）
   - 有助于非英语用户理解

6. **LICENSE 文件重命名**
   - 当前为 `license.txt`，建议统一为 `LICENSE`（大写，无扩展名）
   - 符合 GitHub 等平台的自动识别习惯

### 合规检查清单

- [x] 包含完整的 Apache 2.0 许可证文本
- [x] 包含应用指南附录
- [ ] 脚本文件添加许可证头部（建议）
- [ ] SKILL.md frontmatter 添加 license 字段（建议）
- [ ] 项目 NOTICE 文件包含 skill-creator 归属（建议）

### 相关资源

- Apache License 2.0 官方: https://www.apache.org/licenses/LICENSE-2.0
- SPDX 许可证列表: https://spdx.org/licenses/Apache-2.0
- OSI 认证: https://opensource.org/licenses/Apache-2.0
