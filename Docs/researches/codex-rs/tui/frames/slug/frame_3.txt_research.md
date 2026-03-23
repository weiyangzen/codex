# frame_3.txt 研究文档

## 场景与职责

`frame_3.txt` 是 "slug" 动画变体的第 3 帧，继续展示 ASCII 艺术的动态变化。作为 36 帧循环动画的一部分，该帧在时间上位于第 160-240ms 区间（基于 80ms 帧率）。

### 动画连续性
- 延续 frame_1.txt 和 frame_2.txt 建立的视觉节奏
- 为后续 frame_4.txt 及之后帧提供过渡
- 维持整体动画的流畅性和一致性

## 功能点目的

### 视觉设计目标
- **动态平衡**: 在 17×40 的字符网格内保持视觉重心稳定
- **字符密度变化**: 通过不同字符（d, t, o, e, p, g, x, c, 5, -）的分布创造层次感
- **运动错觉**: 利用帧间微小差异产生旋转或流动的视觉效果

## 具体技术实现

### 文件内容
```
                                       
             d-octtooootd             
         dtt5oeetegooecddeptd         
       tc5pcepgge   egxgppt5det       
      5t5oecttd          eopgeeo      
     p5pe5d5eepod           odoeed    
    5eoo5  -teocoo           e ooe    
    op e    ppoedget          -p5et   
   t-ete     t-eg5oe          xdeoe   
    -gpe    ceptxep-xottdddttdxdgce   
    tocot -5p5cce epeddtgo-tcoeeoee   
    pde e geettg   gpppgggppt555t5    
     ppx ot e              5dtd55     
       od55pot          ttc5gtep      
         odttdppdococtcopcedtg        
           eptpdcxddddxc5dg           
                                       
```

### 技术规格
- **文件大小**: 662 bytes
- **行数**: 17 行（含首尾空行）
- **列数**: 40 字符/行
- **字符集**: {d, t, o, e, p, g, x, c, 5, -, 空格}

### 动画算法
```rust
// 帧索引计算
fn current_frame(&self) -> &'static str {
    let frames = self.frames();  // 返回 FRAMES_SLUG
    let elapsed_ms = self.start.elapsed().as_millis();
    let tick_ms = self.frame_tick.as_millis();  // 80ms
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // idx = 2 时返回本文件内容
}
```

## 关键代码路径与文件引用

### 引用链
```
frame_3.txt
    ▲
    │ include_str!("../frames/slug/frame_3.txt")
frames.rs:frames_for!("slug")[2]
    ▲
    │ const FRAMES_SLUG: [&str; 36]
ascii_animation.rs:AsciiAnimation
    ▲
    │ current_frame()
welcome.rs:WelcomeWidget
    │
    └─ render_ref() 最终渲染
```

## 依赖与外部交互

### 编译依赖
- Rust `include_str!` 宏（编译时文件包含）
- `concat!` 宏用于路径拼接

### 运行时依赖
- `std::time::Instant` 用于计时
- `std::time::Duration` 用于帧率控制

## 风险、边界与改进建议

### 潜在问题
1. **字符显示**: 某些终端可能无法正确显示特定字符组合
2. **文件损坏**: 单帧损坏会影响整个动画序列
3. **性能**: 36 帧全部加载到内存，增加二进制体积

### 改进方向
1. **压缩存储**: 考虑使用差分编码存储帧间变化
2. **懒加载**: 仅在需要时加载特定变体的帧
3. **验证工具**: 构建时验证所有帧的格式一致性
