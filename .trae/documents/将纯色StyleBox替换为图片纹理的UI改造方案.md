## 改造目标
- 全面用图片纹理替换现有 UI 的纯色 StyleBoxFlat，同时保留缺省回退逻辑（图片缺失时仍能使用纯色样式）。
- 覆盖范围：按钮(normal/hover/pressed)、通用面板(panel)、关卡卡片(card_bg)、主菜单背景。
- 保持现有脚本调用点不变（仍通过 GameState.apply_button_style / GameState.get_ui_style 使用），仅替换其内部实现。

## 具体修改点
### 1) GameState.gd：新增纹理样式支持
- 新增函数：get_ui_texture_style(name: String, texture_path: String, margins: Vector4) → StyleBoxTexture
- 在 get_ui_style(name) 内部：先检测对应纹理是否存在，存在则返回 StyleBoxTexture；否则回退到现有 StyleBoxFlat。
- 纹理映射：
  - button_normal → res://Assets/UI/button_normal.png
  - button_hover → res://Assets/UI/button_hover.png
  - button_pressed → res://Assets/UI/button_pressed.png
  - panel → res://Assets/UI/panel_bg.png
  - card_bg → res://Assets/UI/level_card_bg.png
- 九宫格边距（content_margin/border）：为按钮与面板设置合理的边距，用以适配不同尺寸。
- apply_button_style(btn) 保持不变，改为使用 get_ui_style 返回的 StyleBoxTexture/Flat。

### 2) MainMenu 场景背景双层
- 使用已有 Background(TextureRect) 作为底图，加载 res://Assets/Backgrounds/main_menu_bg.png。
- 在其上保留半透明遮罩(ColorRect)，以确保可读性（如 0.3~0.5 alpha）。
- 若图片不存在，回退为纯色背景。

### 3) LevelSelect.gd 与 BattleManager.gd 中的卡片背景
- 保持调用：card.add_theme_stylebox_override("panel", GameState.get_ui_style("card_bg"))。
- 通过 GameState 内部改造实现替换为 StyleBoxTexture（level_card_bg.png）。

### 4) 兼容与回退策略
- 若某图片缺失或路径不正确，UI 自动使用原有 StyleBoxFlat，不影响运行。
- 缓存 StyleBoxTexture 与 StyleBoxFlat，避免重复创建，保持性能。

## 可选增强（在你确认后可一起做）
- 战斗 HUD 图标化：在 Battle.tscn 将 ManpowerLabel/EnemyManpowerLabel 前增加小型 TextureRect 图标（icon_manpower.png / icon_enemy_manpower.png），并用 HBoxContainer 组合。
- 统一主题资源：将边距、圆角、阴影在图片内体现，减少代码层面的样式数值。

## 修改范围与文件
- AutoLoad/GameState.gd：实现纹理样式逻辑与缓存。
- Scenes/MainMenu.tscn + Scripts/MainMenu.gd：启用背景图片与遮罩（若你已放入图片，直接读取）。
- Scripts/LevelSelect.gd、Scripts/BattleManager.gd：无需改动调用处，直接受益于 GameState 改造。

## 验证步骤
- 运行主菜单：检查按钮视觉是否使用图片，背景是否显示 main_menu_bg.png。
- 打开选关：检查关卡卡片背景是否使用 level_card_bg.png。
- 进入战斗胜利界面：奖励卡片背景是否为纹理样式。
- 临时移除某纹理文件：确认自动回退到纯色样式。

请确认以上方案，我将按该方案完成代码改造并自测。