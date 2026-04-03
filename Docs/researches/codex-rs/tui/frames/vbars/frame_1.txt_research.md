# Frame 1 Research Document

## 场景与职责

This is the first frame of the vbars ASCII animation sequence. It represents the initial state of the vertical bars animation, establishing the visual pattern that will evolve throughout the 36-frame cycle. As frame 1, it sets the baseline for the animated effect and introduces the viewer to the dynamic vertical bar pattern.

## 功能点目的

Frame 1 serves as the starting point of the animation loop. It creates an initial visual impression using a distributed pattern of Unicode block characters that suggests movement and energy. The frame contributes to the overall animation flow by establishing the density and distribution of characters that will animate and shift in subsequent frames.

## 具体技术实现

- Frame content:
```
             ▎▋▎▋▌▉▉▌▌▉▊▎             
         ▎▌▊▋▉▍▉▋▉▍▌▏▏▌▎ ▎█▉▎         
       ▊▏▉▏▉▉▉█▍▎   ▎█▉▎█▏▌▏▏▏▉       
      ▌▉▎▍▉█▊▊▎            ▋▉▏▌▏▊     
     ▍▍▌▋█▍▏▍▎▍▍            █▋▏▍▍▊    
    ▏▉ ▉▎  ▏▉▋▌▏▏▊           █▋▍▏▏▊   
   ▉▍█▊▉    █▍▏▉▋█▏▎            ▏▋▏   
   ▏▏▎▏▎     ▊▋▋▏▌▏▉            █▎▏   
   ▏▌▏█▎    ▌▏▏▍▍▏█▋▏▉▉▉▉▉▉▎▉▊ ▌█ ▏   
    ▎▏▌▉  ▎▌▉▎ ▋▉ ▏█▏▎▎▎▋▋▊▊▊▏▋▊▋▊▏   
    ▍▍▎█▍ ▍▍▊▋▋▎   ▎▍▉██▉ ▍▉█▋▊▌▎▋    
     ▉▍▊ █▊ ▎              ▊█▋▉▎▏     
       ▍▍▊▎▍▉▎          ▎▌▎▉▏▎▉█      
         ▍▉▊▍▎ ▉▉▋▌▌▌▌▋▌▉▉▎▊▏▉        
           ▎▉█▉▏▏▏▎▎▎▊▎▌▉▉█           
```

- Character set used: ▎, ▋, ▌, ▉, ▊, █, ▍, ▏ (Unicode block characters)
- Animation timing: 80ms per frame, this is frame 1 of 36
- Frame dimensions: 40 characters wide × 15 lines tall

## 关键代码路径与文件引用

- Source file: `codex-rs/tui/frames/vbars/frame_1.txt`
- Frame registry: `codex-rs/tui/src/frames.rs` (FRAMES_VBARS constant)
- Animation driver: `codex-rs/tui/src/ascii_animation.rs` (AsciiAnimation struct)
- Usage location: `codex-rs/tui/src/onboarding/welcome.rs` (WelcomeWidget)

## 依赖与外部交互

- Used by: `AsciiAnimation::current_frame()` to retrieve frame content
- Rendered by: ratatui's Paragraph widget in WelcomeWidget
- Triggered by: FrameRequester scheduling at 80ms intervals

## 风险、边界与改进建议

- Risk: Terminal must support Unicode block characters
- Boundary: Animation only shows when terminal is at least 60×37 (MIN_ANIMATION_WIDTH × MIN_ANIMATION_HEIGHT)
- Improvement: Could add color support, could make frame rate configurable per variant
