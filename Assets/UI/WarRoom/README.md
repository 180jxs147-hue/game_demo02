# War Room UI assets

Generated with the built-in image_gen tool on 2026-09-15. Original outputs were copied unchanged into this folder. Card illustrations and missing-art handling are unchanged.

- panel_opaque.png (final), panel.png (first variant): charcoal cloth and thin antique bronze frame; used for panel and dialog backgrounds. Runtime scales to 512 × 512 and uses 24 px nine-slice margins. Secondary controls reuse the center region without the frame.
- command.png: oxblood lacquer and brass command frame; used for primary actions and selected navigation. Runtime scales to 768 × 256, with 24 px nine-slice margins.
- camp_backdrop.png: quiet command-tent background for camp, collection, settings, archives and other menu screens.

The original WarOrders assets remain available. Palette: ink #191613, text #e9dfca, muted text #aa9982, bronze #c5a369, border #65533c.

## Validation

Run `Tools/run_menu_visual_smoke.ps1 -GodotPath <path-to-Godot.exe>` after importing the project. The runner places test saves and settings under ignored `output/qa-profile` and restores the parent environment afterwards.

Verified in Godot 4.7.2, OpenGL compatibility rendering:
- MainMenuSmoke: PASS (navigation, settings, resolution, keyboard focus and modal dismissal).
- MenuVisualSmoke: PASS (settings, camp and barracks at 1280 × 720, 1600 × 900 and 1920 × 1080; dropdown, volume, search, tags, synergy and other themed menu screens).
- Screenshots: `output/war-room/`. Logs: `output/MainMenuSmoke.log`, `output/MenuVisualSmoke.log`.
- The sandbox reports a Windows root-certificate-store warning at engine startup; these local UI tests complete without script errors.

## Generation prompts

### panel

Use case: stylized-concept. Asset type: production-ready 2D game UI nine-slice panel texture, square 1024x1024. Create ONE flat front-facing rectangular panel that fills the entire image edge to edge. Chinese historical military strategy game, sophisticated restrained craft, charcoal black woven silk / worn lacquer surface, very subtle warm brown texture, thin aged bronze double hairline border exactly along the outer perimeter, tiny geometric corner engraving. All border decoration confined to outer 28 pixels. Huge clean near-black uniform center suitable for many lines of readable UI text. No perspective, no surrounding space, no objects, no letters, no text, no rivets, no red fabric drapes, no green or teal, no bright grunge, no large ornament. Dark center about #191613. Crisp edges, low contrast texture. An actual reusable texture asset, not a UI mockup or contact sheet.

### button

Use case: stylized-concept. Asset type: production-ready 2D game UI nine-slice button texture, wide 3:1 landscape. Create ONE empty flat front-facing rectangular command button filling the entire image edge to edge, no surrounding space. Refined ancient Chinese military strategy game. Muted deep oxblood red lacquered silk center, thin worn antique brass perimeter, tiny geometric corners. Decoration only at extreme edges, vast clean uniform center. Sophisticated understated materials, no bulky corner plates, no rivets, no illustration, no symbols, no typography, no letters, no text, no green or teal, no perspective, no drop shadow outside asset. Texture is subtly tactile, mostly dark and calm, center about #522a22. Actual reusable game asset for stretching, not a mockup or sheet.

### backdrop

Use case: stylized-concept. Asset type: 16:9 background illustration for a Chinese historical strategy game camp and collection screen. Cinematic painterly view from inside an ancient Chinese command tent at dusk. A quiet very dark charcoal and warm brown canvas interior, faint folded military maps on a low table at bottom edge, shadowed tent fabric on extreme left and right, a narrow glimpse of distant desaturated mountains and small army tents at top center, a restrained muted red banner at far right. Composition specifically for UI overlay: 85 percent of the whole image is calm softly textured dark negative space; all props confined to very bottom and extreme edges, no focal object center. No characters, no text, no UI, no frames, no symbols, no green or teal hues, no bright white sky, no bright fire. Atmospheric soft indirect bronze dusk light, premium hand painted game environment, low contrast behind interface. Palette warm charcoal #171411 and earth brown, quiet somber tone.

### Panel refinement

Edit this existing game panel texture only. Preserve the exact square shape, the thin antique bronze perimeter and small geometric corners, the quiet charcoal woven material, and edge-to-edge framing. Fix opacity: the ENTIRE image must be FULLY OPAQUE, including every pixel of the border and the dark center. Remove all transparent and semi-transparent regions, any misty gray bloom, any white or smoky haze around the edges. Background behind bronze is solid very dark warm charcoal #191613 all the way to the outermost pixel. Keep texture subtle and fine, with a uniform dark center and restrained bronze frame. No new symbols, no text, no green, no glow, no external padding. This is a flat game UI texture that will be nine-sliced and placed over busy backgrounds; it must completely conceal the scene behind it.
