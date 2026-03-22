# LICENSE 研究文档

## 场景与职责

`LICENSE` 文件是项目的许可证文件，定义了他人如何使用、修改和分发该项目的法律条款。Codex 项目采用 **Apache License 2.0**，这是一种广泛使用的开源许可证，以其商业友好性和专利保护而闻名。

该文件位于项目根目录，是开源项目的标准组成部分，对于项目的法律合规性和社区贡献至关重要。

## 功能点目的

### 1. 法律授权

Apache License 2.0 授予用户以下权利：
- **使用**：可以将软件用于任何目的
- **修改**：可以修改源代码
- **分发**：可以分发原始或修改后的版本
- **专利授权**：明确授予专利使用权
- **再许可**：可以基于 Apache 2.0 或其他许可证再许可

### 2. 专利保护

Apache 2.0 的重要特性之一是专利授权条款（第 3 条）：
- 贡献者授予用户专利使用权
- 如果用户起诉项目侵犯专利，则专利授权终止
- 这提供了防御性专利保护

### 3. 归属要求

许可证要求保留：
- 版权声明
- 许可证文本
- 免责声明
- 贡献声明（如适用）

### 4. 免责声明

第 7-9 条明确声明：
- 软件按"原样"提供
- 无担保或条件
- 贡献者不对损害负责

## 具体技术实现

### 许可证结构

Apache License 2.0 包含以下主要部分：

1. **定义**（第 1 条）
   - "License", "Licensor", "Legal Entity", "You", "Source", "Object", "Work", "Derivative Works", "Contribution", "Contributor"

2. **授权许可**（第 2-3 条）
   - 版权许可
   - 专利许可

3. **再分发条件**（第 4 条）
   - 保留版权声明
   - 保留许可声明
   - 保留免责声明
   - 修改声明

4. **贡献提交**（第 5 条）
   - 除非明确说明，否则贡献按许可证条款提交

5. **商标**（第 6 条）
   - 许可证不授予商标使用权

6. **免责声明和责任限制**（第 7-9 条）
   - 无担保
   - 责任限制

7. **附录**：如何将许可证应用于作品

### 版权声明

```
Copyright 2025 OpenAI
```

- 版权年份：2025
- 版权持有者：OpenAI

### 应用许可证的模板

许可证附录提供了如何将 Apache 2.0 应用于新文件的模板：

```
Copyright [yyyy] [name of copyright owner]

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

## 关键代码路径与文件引用

### 相关文件

1. **NOTICE**（如果存在）
   - 包含归属通知
   - Apache 2.0 要求保留 NOTICE 文件内容

2. **package.json**
   ```json
   "license": "Apache-2.0"
   ```

3. **codex-rs/Cargo.toml**
   ```toml
   license = "Apache-2.0"
   ```

4. **README.md**
   - 通常包含许可证徽章或说明

5. **CONTRIBUTING.md**（如果存在）
   - 贡献者协议
   - 与许可证相关的贡献条款

### 许可证应用范围

```
LICENSE (根目录)
    ├── 适用于整个项目
    ├── 各子项目通过 package.json/Cargo.toml 引用
    └── 源代码文件通常包含许可证头
```

## 依赖与外部交互

### 开源合规性

**依赖许可证兼容性**：
- Apache 2.0 与大多数开源许可证兼容
- 与 MIT、BSD、ISC 等宽松许可证兼容
- 与 GPLv3 兼容（Apache 2.0 可以包含在 GPLv3 项目中）
- 与 GPLv2 不兼容（专利条款冲突）

**Codex 项目的依赖**：
- Rust crates：通过 Cargo.toml 管理
- npm 包：通过 package.json 管理
- 需要确保所有依赖的许可证与 Apache 2.0 兼容

### GitHub 集成

**自动检测**：
- GitHub 自动识别 LICENSE 文件
- 在仓库页面显示许可证类型
- 提供许可证摘要

**API 访问**：
```bash
# 获取许可证信息
curl https://api.github.com/repos/openai/codex/license
```

### 与贡献者协议的关系

Apache 2.0 第 5 条规定：
> "Unless You explicitly state otherwise, any Contribution intentionally submitted for inclusion in the Work by You to the Licensor shall be under the terms and conditions of this License"

这意味着：
- 提交 PR 即表示同意按 Apache 2.0 许可贡献
- 不需要单独的贡献者许可协议（CLA）
- 但某些项目可能仍要求 CLA

## 风险、边界与改进建议

### 潜在风险

1. **许可证头缺失**
   - 源代码文件可能缺少许可证头
   - 建议在每个源文件顶部添加版权声明

2. **依赖许可证冲突**
   - 某些依赖可能使用不兼容的许可证
   - 需要定期审计依赖许可证

3. **版权年份未更新**
   - 当前为 2025
   - 需要在新年份更新

4. **NOTICE 文件**
   - 如果有第三方代码，需要在 NOTICE 中声明
   - 当前项目有 NOTICE 文件，需要确保内容完整

### 边界情况

1. **子项目许可证**
   - codex-cli、sdk/typescript 等子项目应继承根目录许可证
   - 或在各自目录中包含 LICENSE 文件

2. **生成代码**
   - OpenAPI 生成的代码的许可证归属
   - 通常应保留原许可证

3. **文档和示例**
   - 文档可能使用不同的许可（如 CC-BY）
   - 需要明确说明

### 改进建议

1. **添加许可证头到源文件**
   ```rust
   // Copyright 2025 OpenAI
   //
   // Licensed under the Apache License, Version 2.0 (the "License");
   // you may not use this file except in compliance with the License.
   // You may obtain a copy of the License at
   //
   //     http://www.apache.org/licenses/LICENSE-2.0
   //
   // Unless required by applicable law or agreed to in writing, software
   // distributed under the License is distributed on an "AS IS" BASIS,
   // WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   // See the License for the specific language governing permissions and
   // limitations under the License.
   ```

2. **添加 LICENSE 徽章到 README**
   ```markdown
   [![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
   ```

3. **定期许可证审计**
   ```bash
   # Rust 依赖
   cargo license

   # Node.js 依赖
   npx license-checker --summary
   ```

4. **更新版权年份**
   - 每年更新 LICENSE 文件中的年份
   - 或使用范围格式："2025-2026"

5. **完善 NOTICE 文件**
   ```
   Codex
   Copyright 2025 OpenAI

   This product includes software developed at OpenAI.

   Third-party dependencies:
   - Rust: See codex-rs/Cargo.toml
   - Node.js: See package.json
   ```

6. **添加许可证说明到文档**
   ```markdown
   ## License

   This project is licensed under the Apache License 2.0.
   See [LICENSE](LICENSE) for details.

   ### Third-party Licenses

   This project uses open source software. See the respective
   LICENSE files in the dependencies for details.
   ```

### 使用示例

```bash
# 查看许可证
cat LICENSE

# 检查依赖许可证（Rust）
cargo install cargo-license
cargo license

# 检查依赖许可证（Node.js）
npx license-checker --summary

# 生成许可证报告
npx license-checker --json > licenses.json
```

### 与其他许可证的对比

| 许可证 | 专利保护 | 商业使用 | 修改后闭源 | 传染性 |
|--------|---------|---------|-----------|--------|
| Apache 2.0 | 是 | 是 | 是 | 无 |
| MIT | 否 | 是 | 是 | 无 |
| GPL v3 | 是 | 是 | 否 | 强 |
| BSD | 否 | 是 | 是 | 无 |

**Apache 2.0 的优势**：
- 明确的专利授权
- 商业友好
- 法律条款清晰
- 广泛接受

**Apache 2.0 的考虑**：
- 需要保留 NOTICE 文件
- 修改需要声明
- 文件较长（相比 MIT）
