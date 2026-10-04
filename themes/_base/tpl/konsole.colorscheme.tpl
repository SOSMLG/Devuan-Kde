[General]
Description=@PALETTE_NAME@
Opacity=0.92
Wallpaper=

[Background]
Color=@RG_C_BG@

[BackgroundIntense]
Color=@RG_C_BG@

[Foreground]
Color=@RG_C_TEXT@

[ForegroundIntense]
Color=@RG_C_TEXT@

[Color0]
Color=@RG_C_0@

[Color0Intense]
Color=@RG_C_8@

[Color1]
Color=@RG_C_1@

[Color1Intense]
Color=@RG_C_9@

[Color2]
Color=@RG_C_2@

[Color2Intense]
Color=@RG_C_10@

[Color3]
Color=@RG_C_3@

[Color3Intense]
Color=@RG_C_11@

[Color4]
Color=@RG_C_4@

[Color4Intense]
Color=@RG_C_12@

[Color5]
Color=@RG_C_5@

[Color5Intense]
Color=@RG_C_13@

[Color6]
Color=@RG_C_6@

[Color6Intense]
Color=@RG_C_14@

[Color7]
Color=@RG_C_7@

[Color7Intense]
Color=@RG_C_15@

# Cursor and selection. Without these three sections Konsole silently falls back
# to its own defaults, which is how a scheme can match Alacritry on all 16 ANSI
# colours and still look different: the block cursor and the selection highlight
# are drawn from here and nowhere else. C_ACCENT is the cursor, C_SURFACE0 the
# selection background, C_TEXT the selected text -- the same roles they have in
# the Alacritry config these palettes are derived from.
[Cursor]
Color=@RG_C_ACCENT@
ColorIntense=@RG_C_ACCENT@

[SelectionBackground]
Color=@RG_C_SURFACE0@
ColorIntense=@RG_C_SURFACE0@

[SelectionForeground]
Color=@RG_C_TEXT@
ColorIntense=@RG_C_TEXT@