# COPYING 研究文档

## 场景与职责

`COPYING` 文件包含 bubblewrap 项目的完整许可证文本，即 **GNU 宽通用公共许可证第 2 版（GNU LGPL v2）**。该文件是项目法律基础的核心，定义了用户使用、修改和分发软件的权利与义务。

文件同时通过符号链接 `LICENSE` 提供，确保不同查找习惯的用户都能找到许可证信息。

## 功能点目的

1. **法律授权**：授予用户合法使用、研究、修改和分发软件的权利
2. ** copyleft 保护**：确保衍生作品保持开源，促进自由软件生态
3. **责任限制**：明确免责声明，保护贡献者免受法律责任
4. **专利保护**：防止软件被专利化而限制自由使用

## 具体技术实现

### 许可证类型

| 属性 | 值 |
|------|-----|
| 许可证 | GNU Library General Public License v2 (LGPL v2) |
| 后续版本 | 允许升级到后续版本（"any later version"） |
| 文件大小 | 25,383 字节（481 行） |

### LGPL v2 核心特征

#### 与 GPL 的区别
- **库专用**：专为软件库设计，允许非自由程序链接使用
- **较弱 copyleft**：链接 LGPL 库的程序不需要开源
- **修改需开源**：对 LGPL 库本身的修改必须开源

#### 关键条款

**第 0 条：定义**
- 明确 "Library"、"work based on the Library"、"Source code" 的定义
- 区分 "修改库" 和 "使用库"

**第 2 条：修改条款**
- 修改后的作品必须是软件库
- 必须包含修改声明和日期
- 必须允许第三方在 LGPL 下使用

**第 6 条：链接例外**
- 允许将库与非自由程序链接
- 产生的可执行文件不受 LGPL 约束
- 但必须提供库的源代码

### 文件结构

```
COPYING (481 行)
├── 标题和版本声明 (1-10)
├── 序言 (12-101)
│   └── 解释 LGPL 的设计哲学和与 GPL 的区别
├── 条款和条件 (102-437)
│   ├── 第 0 条：定义 (105-135)
│   ├── 第 1 条： verbatim 复制 (136-148)
│   ├── 第 2 条：修改 (149-196)
│   ├── 第 3 条：切换到 GPL (197-212)
│   ├── 第 4 条：目标代码分发 (213-225)
│   ├── 第 5 条：使用库的作品 (226-256)
│   ├── 第 6 条：链接例外 (257-310)
│   ├── 第 7 条：合并库 (311-327)
│   ├── 第 8 条：其他限制 (328-334)
│   ├── 第 9 条：接受许可 (335-343)
│   ├── 第 10 条：自动授权 (344-351)
│   ├── 第 11 条：专利 (352-382)
│   ├── 第 12 条：地域限制 (383-390)
│   ├── 第 13 条：新版本 (391-403)
│   ├── 第 14 条：例外请求 (404-412)
│   └── 第 15-16 条：免责声明 (413-437)
└── 应用指南 (438-481)
    └── 如何在新库中应用 LGPL
```

## 关键代码路径与文件引用

- **文件位置**: `codex-rs/vendor/bubblewrap/COPYING`
- **符号链接**: `codex-rs/vendor/bubblewrap/LICENSE -> COPYING`
- **关联文件**:
  - 源代码文件头部的 SPDX 标识：`SPDX-License-Identifier: LGPL-2.0-or-later`
  - `NOTICE` - 可能的附加版权声明

### SPDX 标识

项目源代码文件包含标准 SPDX 标识：
```c
/* bubblewrap
 * Copyright (C) 2016 Alexander Larsson
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */
```

这符合 [REUSE 规范](https://reuse.software/)，使许可证信息可被自动化工具识别。

## 依赖与外部交互

### 法律依赖
- **Free Software Foundation**: LGPL 的制定和维护者
- **各国版权法**: LGPL 基于国际版权法律框架

### 生态交互

bubblewrap 作为 LGPL 库，与以下项目类型交互：

| 项目类型 | 交互方式 | 许可证要求 |
|---------|---------|-----------|
| Flatpak | 调用 bubblewrap | 无特殊要求（独立程序） |
| rpm-ostree | 调用 bubblewrap | 无特殊要求 |
| bwrap-oci | 调用 bubblewrap | 无特殊要求 |
| 商业软件 | 可能调用 bubblewrap | 需遵守 LGPL 第 6 条 |

### 分发场景

1. **Linux 发行版打包**
   - 必须提供 LGPL 完整文本（本文件）
   - 必须提供 bubblewrap 源代码或获取方式

2. **静态链接场景**
   - 若将 bubblewrap 静态链接到非 GPL 程序
   - 需要提供对象文件以便重新链接

## 风险、边界与改进建议

### 风险

1. **许可证兼容性**
   - LGPL v2 与某些许可证（如 Apache 2.0）存在专利条款冲突
   - 与 GPL v3 的兼容性需要仔细处理

2. **静态链接争议**
   - LGPL 对静态链接的解释存在争议
   - 某些嵌入式场景可能难以满足提供对象文件的要求

3. **"或更高版本"条款**
   - "any later version" 允许 FSF 未来版本的条款自动适用
   - 存在对未来版本条款不可控的风险

### 边界

- 不保护商标和专利（除第 11 条的基础保护外）
- 不提供担保（第 15-16 条明确免责声明）
- 不限制合理使用（美国版权法）或类似例外

### 改进建议

1. **考虑许可证升级**
   ```
   当前: LGPL-2.0-or-later
   建议评估: LGPL-3.0-or-later
   
   优势:
   - 更清晰的专利授权
   - 与 Apache 2.0 更好的兼容性
   - 更强的反 tivoization 保护
   
   风险:
   - 需要所有贡献者同意
   - 可能影响现有分发者
   ```

2. **添加许可证头模板**
   在项目中提供标准许可证头模板，便于新文件使用：
   ```c
   /* bubblewrap
    * Copyright (C) [YEAR] [AUTHOR]
    * SPDX-License-Identifier: LGPL-2.0-or-later
    *
    * This program is free software; you can redistribute it and/or
    * modify it under the terms of the GNU Lesser General Public
    * License as published by the Free Software Foundation; either
    * version 2 of the License, or (at your option) any later version.
    */
   ```

3. **REUSE 合规检查**
   添加 CI 检查确保所有文件都有 SPDX 标识：
   ```yaml
   - name: REUSE Compliance Check
     uses: fsfe/reuse-action@v1
   ```

4. **版权声明文件**
   考虑添加 `AUTHORS` 或 `CONTRIBUTORS` 文件，记录版权持有者

5. **许可证解释文档**
   添加简化的许可证 FAQ，帮助用户理解：
   - 可以做什么（使用、修改、分发）
   - 必须做什么（保留版权声明、提供源代码）
   - 不能做什么（移除许可证、添加额外限制）

## 与项目整体的关系

### 在开源治理中的位置

```
法律框架
├── COPYING (本文件) - 核心许可证
├── LICENSE -> COPYING - 符号链接
├── NOTICE - 附加声明（如有）
├── AUTHORS - 贡献者列表（如有）
└── 源代码 SPDX 标识 - 文件级许可声明
```

### 对 bubblewrap 的特殊意义

1. **安全工具的信任基础**
   - 作为 setuid root 工具，开源许可证允许安全审计
   - 用户可验证代码无恶意功能

2. **容器生态的集成**
   - LGPL 允许被各种容器运行时调用
   - 不强制要求整个容器栈开源

3. **商业友好性**
   - 企业可在专有产品中使用 bubblewrap
   - 促进更广泛的采用和贡献

## 相关资源

- [GNU LGPL v2.1 官方文本](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html)
- [GNU LGPL v3 官方文本](https://www.gnu.org/licenses/lgpl-3.0.html)
- [FSF 许可证列表](https://www.gnu.org/licenses/license-list.html)
- [SPDX 许可证标识符](https://spdx.org/licenses/)
- [Choose a License](https://choosealicense.com/)（许可证选择指南）
