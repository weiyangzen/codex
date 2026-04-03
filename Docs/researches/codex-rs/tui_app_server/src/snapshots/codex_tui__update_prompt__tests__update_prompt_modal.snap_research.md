# 研究文档：update_prompt_modal.snap

## 场景与职责

此快照测试验证 Codex CLI 更新提示模态框的显示效果。当有新版本可用时，向用户展示更新选项。

## 功能点目的

1. **更新通知**：告知用户有新版本可用
2. **版本信息**：显示当前版本和最新版本
3. **更新选项**：提供多种更新选择

## 具体技术实现

### 快照输出分析

```
  ✨ Update available! 0.0.0 -> 9.9.9

  Release notes: https://github.com/openai/codex/releases/latest

› 1. Update now (runs `npm install -g @openai/codex@latest`)                    
  2. Skip
  3. Skip until next version

  Press enter to continue
```

界面元素：
- 标题：`✨ Update available!` + 版本信息
- 发布说明链接
- 选项菜单：
  1. 立即更新（显示具体命令）
  2. 跳过
  3. 跳过直到下个版本
- 操作提示

### 更新提示实现

```rust
pub struct UpdatePrompt {
    current_version: String,
    latest_version: String,
    selected_option: UpdateOption,
}

#[derive(Clone, Copy)]
enum UpdateOption {
    UpdateNow,
    Skip,
    SkipUntilNext,
}

impl UpdatePrompt {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 渲染标题
        let title = format!("✨ Update available! {} -> {}", 
            self.current_version, 
            self.latest_version);
        
        // 渲染选项...
    }
}
```

## 关键代码路径与文件引用

1. **更新提示**：
   - `codex-rs/tui/src/update_prompt.rs`

2. **版本信息**：
   - `crate::version::CODEX_CLI_VERSION`

## 依赖与外部交互

### 版本检查
- GitHub API 或更新服务器
- 版本比较逻辑

## 风险、边界与改进建议

### 潜在风险
1. **网络问题**：无法获取版本信息
2. **权限问题**：更新可能需要管理员权限
3. **中断风险**：更新过程中断可能导致安装损坏

### 边界情况
1. 预发布版本
2. 降级场景
3. 离线环境

### 改进建议
1. 添加更新进度显示
2. 支持后台下载
3. 添加更新日志预览
4. 支持自动更新配置
