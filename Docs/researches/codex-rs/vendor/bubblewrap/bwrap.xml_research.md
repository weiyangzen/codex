# bwrap.xml 研究文档

## 场景与职责

`bwrap.xml` 是 Bubblewrap 项目的 DocBook XML 格式的手册页源文件，用于生成 `bwrap(1)` 手册页。Bubblewrap 是一个无特权（可选 setuid）的低级沙箱工具，用于在 Linux 上创建容器化环境。

该文件作为项目的官方文档来源，定义了：
- bwrap 命令的完整使用说明
- 所有命令行选项的详细描述
- 内核命名空间相关选项（user、ipc、pid、net、uts、cgroup）
- 文件系统挂载选项（bind、overlay、tmpfs、proc、dev 等）
- 安全锁定选项（seccomp、capabilities、SELinux 标签等）
- 环境变量和退出状态说明

## 功能点目的

### 1. 文档生成
- 通过 `xsltproc` 将 DocBook XML 转换为 roff 格式的手册页
- 在构建时生成 `bwrap.1` 手册页（见 `meson.build` 第 126-163 行）

### 2. 用户指南
- 为系统管理员和开发者提供完整的命令参考
- 解释沙箱的工作原理和限制
- 提供安全使用建议

### 3. 选项分类文档化

| 类别 | 选项示例 | 用途 |
|------|----------|------|
| 命名空间 | `--unshare-user`, `--unshare-net` | 隔离用户、网络等资源 |
| 文件系统 | `--bind`, `--ro-bind`, `--overlay` | 挂载主机目录到沙箱 |
| 设备 | `--dev`, `--proc` | 创建虚拟文件系统 |
| 安全 | `--seccomp`, `--cap-drop` | 限制系统调用和权限 |
| 进程 | `--die-with-parent`, `--new-session` | 进程生命周期管理 |

## 具体技术实现

### DocBook XML 结构

```xml
<refentry id="bwrap">
  <refentryinfo>      <!-- 元数据：作者、版本 -->
  <refmeta>           <!-- 手册页标题、章节 -->
  <refnamediv>        <!-- 命令名称和简要描述 -->
  <refsynopsisdiv>    <!-- 命令语法概要 -->
  <refsect1>          <!-- 详细章节：描述、选项、环境 -->
```

### 关键 XML 元素

1. **命令语法定义**（第 36-41 行）：
```xml
<cmdsynopsis>
  <command>bwrap</command>
  <arg choice="opt" rep="repeat"><replaceable>OPTION</replaceable></arg>
  <arg choice="opt"><replaceable>COMMAND</replaceable></arg>
</cmdsynopsis>
```

2. **选项列表**（第 78-620 行）：
   - 使用 `<variablelist>` 组织选项
   - 每个选项使用 `<varlistentry>` 定义
   - 支持 `<term>` 和 `<listitem>` 描述选项和说明

3. **交叉引用**：
   - 使用 `<citerefentry>` 引用其他手册页（如 `syslog(3)`）
   - 使用 `<ulink>` 引用外部文档（如内核文档）

### 构建集成

在 `meson.build` 中：
```meson
if build_man_page
  custom_target(
    'bwrap.1',
    output : 'bwrap.1',
    input : 'bwrap.xml',
    command : [
      xsltproc,
      '--nonet',
      '--stringparam', 'man.output.quietly', '1',
      ...
    ],
    install : true,
    install_dir : get_option('mandir') / 'man1',
  )
endif
```

## 关键代码路径与文件引用

### 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `meson.build` | 调用方 | 定义手册页构建规则 |
| `bubblewrap.c` | 实现 | 包含所有选项的实际实现 |
| `bwrap.1` | 生成物 | 编译后的手册页 |

### 选项实现对应

XML 中定义的选项在 `bubblewrap.c` 中有对应实现：

| XML 选项 | C 代码位置 | 功能 |
|----------|------------|------|
| `--unshare-user` | 第 1887-1889 行 | `opt_unshare_user = true` |
| `--bind` | 第 1956-1969 行 | `SETUP_BIND_MOUNT` |
| `--overlay` | 第 2035-2057 行 | `SETUP_OVERLAY_MOUNT` |
| `--seccomp` | 第 2406-2428 行 | `seccomp_program_new()` |

## 依赖与外部交互

### 构建依赖

1. **xsltproc**：XSLT 处理器，用于转换 DocBook XML
2. **DocBook XSL**：样式表，定义 XML 到 roff 的转换规则
   - URL: `http://docbook.sourceforge.net/release/xsl/current/manpages/docbook.xsl`

### 运行时依赖

手册页本身无运行时依赖，但描述的 bwrap 工具依赖：
- Linux 内核 3.8+（用户命名空间支持）
- libcap（capabilities 支持）
- 可选：libselinux（SELinux 支持）

## 风险、边界与改进建议

### 风险

1. **文档与代码不同步**：
   - 风险：代码新增选项后，XML 未更新
   - 缓解：代码审查时检查文档更新

2. **XSLT 处理失败**：
   - 风险：网络问题导致 XSL 下载失败
   - 缓解：使用 `--nonet` 标志，依赖本地 XSL

3. **格式兼容性问题**：
   - 风险：不同版本的 xsltproc 生成不同输出
   - 缓解：在 CI 中测试多种环境

### 边界

1. **仅支持类 Unix 系统**：手册页格式为 roff，主要用于 Linux
2. **需要完整 DocBook 工具链**：构建依赖较重
3. **静态文档**：无法动态反映运行时配置

### 改进建议

1. **自动化文档检查**：
   - 添加 CI 检查确保所有 `--help` 选项都在 XML 中有文档
   - 使用脚本比较 `bubblewrap.c` 中的选项与 XML 定义

2. **多格式输出**：
   - 除手册页外，可生成 HTML 在线文档
   - 添加 `--help` 输出与手册页的交叉验证

3. **国际化支持**：
   - 当前仅英文，可考虑添加翻译支持
   - 使用 gettext 系统管理多语言文档

4. **示例丰富化**：
   - 添加更多实际使用示例
   - 包含常见用例（如 Flatpak、rpm-ostree）的配置示例
