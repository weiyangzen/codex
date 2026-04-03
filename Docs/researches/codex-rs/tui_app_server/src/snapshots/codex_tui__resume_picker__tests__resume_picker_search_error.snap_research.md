# 研究文档：resume_picker_search_error.snap

## 场景与职责

此快照测试验证会话恢复选择器在搜索出错时的错误显示。当读取会话元数据失败时，应该向用户显示友好的错误信息。

## 功能点目的

1. **错误信息展示**：清晰显示错误原因
2. **友好提示**：使用用户能理解的语言描述错误
3. **恢复建议**：如果可能，提供恢复建议

## 具体技术实现

### 快照输出分析

```
Failed to read session metadata from /tmp/missing.jsonl
```

设计特点：
- 简洁的错误信息
- 包含具体的文件路径
- 明确错误类型（读取失败）

### 错误处理逻辑

```rust
fn load_sessions(session_dir: &Path) -> Result<Vec<SessionMetadata>, LoadError> {
    let mut sessions = vec![];
    
    for entry in fs::read_dir(session_dir)? {
        let entry = entry?;
        let path = entry.path();
        
        match load_session_metadata(&path) {
            Ok(metadata) => sessions.push(metadata),
            Err(e) => {
                // 记录错误但继续加载其他会话
                error!("Failed to read session metadata from {}: {}", path.display(), e);
                return Err(LoadError::ReadFailed(path, e));
            }
        }
    }
    
    Ok(sessions)
}
```

## 关键代码路径与文件引用

1. **错误处理**：
   - `codex-rs/tui/src/resume_picker.rs`
   - `codex_core::session`

2. **日志记录**：
   - `tracing::error`

## 依赖与外部交互

### 错误类型
- `std::io::Error` - IO 错误
- 自定义 `LoadError` - 加载错误

## 风险、边界与改进建议

### 潜在风险
1. **信息泄露**：错误信息可能暴露敏感路径
2. **用户困惑**：技术错误信息可能让用户困惑

### 边界情况
1. 权限不足
2. 文件格式错误
3. 磁盘空间不足

### 改进建议
1. 区分用户错误和系统错误
2. 提供重试按钮
3. 添加 "忽略并继续" 选项
4. 提供手动恢复指南
