#!/usr/bin/env bash
# themes/palettes.sh — every shipped palette, in one file.
#
# This used to be themes/<id>/palette.sh, one directory per palette: 11 files
# in 11 directories, all defining the same variables, discovered by globbing
# themes/*/ and sourced by path. Consolidated because the file sprawl was
# costing more than it bought —
#
#   * `git add themes/` moved 22 entries to add a single colour change, and a
#     fresh clone carried 11 directories to explain 11 functions;
#   * list_palettes() shelled out twice per palette (once for PALETTE_SHORT,
#     once for PALETTE_NAME) — 22 subshells to print 11 lines, because
#     reading a variable set by a sourced file needs a subshell;
#   * nothing was gained from the directory: no palette shipped an asset of
#     its own, and templates already live once in themes/_base/tpl/.
#
# Each palette is a function palette_<id>() that assigns the variables
# documented in _PALETTE_VARS (scripts/lib/theme.sh). PALETTE_ID is set inside
# its own function and load_palette() checks it against the id being loaded,
# so a copy-pasted block cannot answer to the wrong name.
#
# Bodies are kept verbatim from the old per-palette files — comments and all —
# so `git log -p themes/darkmatter/palette.sh` still reads as the history of
# the corresponding function here. To add a palette: add the id to PALETTE_IDS
# (the order the picker shows) and one function. Nothing else needs touching.

# Order matters: this is the order the interactive picker lists.
PALETTE_IDS=(
    darkmatter
    darkmatter-orange
    dracula
    frappe
    gruvbox
    mocha-blue
    mocha-red
    moe-dark
    nord
    otto
    solarized
    tokyo-night
)

# --------------------------------------------------------------------------
# palette_darkmatter() — id "darkmatter" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_darkmatter() {
PALETTE_ID="darkmatter"
PALETTE_NAME="Darkmatter"
PALETTE_SHORT="Darkmatter"
PALETTE_DESC="The Darkmatter rice — near-black shell with the red #e75353 accent, matching the XFCE/xfwm4 theme this toolkit grew up alongside."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=121113
C_MANTLE=171618
C_CRUST=0d0c0e
C_SURFACE0=1c1b1d
C_SURFACE1=222222
C_OVERLAY0=2b2b2b
C_OVERLAY1=333333
C_TEXT=ffffff
C_SUBTEXT0=c1c1c1
C_SUBTEXT1=9a9a9a

C_ACCENT=e75353
C_ACCENT_FG=121113
C_ACCENT_DIM=8f3a3a

C_0=222222
C_1=e75353
C_2=5f8787
C_3=fbcb97
C_4=8ba4b0
C_5=c9a1c9
C_6=7ba37b
C_7=c1c1c1
C_8=2b2b2b
C_9=f07777
C_10=7ba3a3
C_11=fbd5ad
C_12=a5bfc9
C_13=d9b9d9
C_14=9bc09b
C_15=ffffff
}

# --------------------------------------------------------------------------
# palette_darkmatter_orange() — id "darkmatter-orange" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_darkmatter_orange() {
PALETTE_ID="darkmatter-orange"
PALETTE_NAME="Darkmatter (Upstream Orange)"
PALETTE_SHORT="DarkmatterOrange"
PALETTE_DESC="Darkmatter with the upstream accent left untouched (#e78a53) instead of the red remap — for people who want the theme exactly as the author shipped it."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=121113
C_MANTLE=171618
C_CRUST=0d0c0e
C_SURFACE0=1c1b1d
C_SURFACE1=222222
C_OVERLAY0=2b2b2b
C_OVERLAY1=333333
C_TEXT=ffffff
C_SUBTEXT0=c1c1c1
C_SUBTEXT1=9a9a9a

C_ACCENT=e78a53
C_ACCENT_FG=121113
C_ACCENT_DIM=8f5a3a

C_0=222222
C_1=e78a53
C_2=5f8787
C_3=fbcb97
C_4=8ba4b0
C_5=c9a1c9
C_6=7ba37b
C_7=c1c1c1
C_8=2b2b2b
C_9=f0a478
C_10=7ba3a3
C_11=fbd5ad
C_12=a5bfc9
C_13=d9b9d9
C_14=9bc09b
C_15=ffffff
}

# --------------------------------------------------------------------------
# palette_dracula() — id "dracula" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_dracula() {
PALETTE_ID="dracula"
PALETTE_NAME="Dracula"
PALETTE_SHORT="Dracula"
PALETTE_DESC="The classic Dracula color scheme with its signature pink accent."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=282a36
C_MANTLE=21222c
C_CRUST=191a21
C_SURFACE0=44475a
C_SURFACE1=3b3d4f
C_OVERLAY0=6272a4
C_OVERLAY1=6d80b7
C_TEXT=f8f8f2
C_SUBTEXT0=6272a4
C_SUBTEXT1=8f9ac2

C_ACCENT=ff79c6
C_ACCENT_FG=282a36
C_ACCENT_DIM=ffb4dc

C_0=21222c
C_1=ff5555
C_2=50fa7b
C_3=f1fa8c
C_4=bd93f9
C_5=ff79c6
C_6=8be9fd
C_7=f8f8f2
C_8=424450
C_9=ff5555
C_10=50fa7b
C_11=f1fa8c
C_12=bd93f9
C_13=ff79c6
C_14=8be9fd
C_15=f8f8f2
}

# --------------------------------------------------------------------------
# palette_frappe() — id "frappe" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_frappe() {
PALETTE_ID="frappe"
PALETTE_NAME="Catppuccin Frappe"
PALETTE_SHORT="CatppuccinFrappe"
PALETTE_DESC="Catppuccin Frappe — a lighter, blue-washed take on Catppuccin."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=303446
C_MANTLE=292c3c
C_CRUST=232634
C_SURFACE0=414559
C_SURFACE1=51576d
C_OVERLAY0=737994
C_OVERLAY1=838ba7
C_TEXT=c6d0f5
C_SUBTEXT0=a5adce
C_SUBTEXT1=b5bfe2

C_ACCENT=8caaee
C_ACCENT_FG=303446
C_ACCENT_DIM=a6c0f2

C_0=51576d
C_1=e78284
C_2=a6d189
C_3=e5c890
C_4=8caaee
C_5=f4b8e4
C_6=81c8be
C_7=b5bfe2
C_8=626880
C_9=e78284
C_10=a6d189
C_11=e5c890
C_12=8caaee
C_13=f4b8e4
C_14=81c8be
C_15=a5adce
}

# --------------------------------------------------------------------------
# palette_gruvbox() — id "gruvbox" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_gruvbox() {
PALETTE_ID="gruvbox"
PALETTE_NAME="Gruvbox Dark"
PALETTE_SHORT="GruvboxDark"
PALETTE_DESC="Gruvbox (dark, medium) — warm, retro-groove colors with a yellow accent."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=282828
C_MANTLE=1d2021
C_CRUST=141617
C_SURFACE0=3c3836
C_SURFACE1=504945
C_OVERLAY0=7c6f64
C_OVERLAY1=928374
C_TEXT=ebdbb2
C_SUBTEXT0=a89984
C_SUBTEXT1=bdae93

C_ACCENT=fabd2f
C_ACCENT_FG=282828
C_ACCENT_DIM=fcd66d

C_0=282828
C_1=cc241d
C_2=98971a
C_3=d79921
C_4=458588
C_5=b16286
C_6=689d6a
C_7=a89984
C_8=928374
C_9=fb4934
C_10=b8bb26
C_11=fabd2f
C_12=83a598
C_13=d3869b
C_14=8ec07c
C_15=ebdbb2
}

# --------------------------------------------------------------------------
# palette_mocha_blue() — id "mocha-blue" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_mocha_blue() {
PALETTE_ID="mocha-blue"
PALETTE_NAME="Catppuccin Mocha (Blue)"
PALETTE_SHORT="CatppuccinBlue"
PALETTE_DESC="Catppuccin Mocha with the calm sapphire/blue accent."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=1e1e2e
C_MANTLE=181825
C_CRUST=11111b
C_SURFACE0=313244
C_SURFACE1=45475a
C_OVERLAY0=6c7086
C_OVERLAY1=7f849c
C_TEXT=cdd6f4
C_SUBTEXT0=a6adc8
C_SUBTEXT1=bac2de

C_ACCENT=89b4fa
C_ACCENT_FG=1e1e2e
C_ACCENT_DIM=a4c7fb

C_0=45475a
C_1=f38ba8
C_2=a6e3a1
C_3=f9e2af
C_4=89b4fa
C_5=f5c2e7
C_6=94e2d5
C_7=bac2de
C_8=585b70
C_9=f38ba8
C_10=a6e3a1
C_11=f9e2af
C_12=89b4fa
C_13=f5c2e7
C_14=94e2d5
C_15=a6adc8
}

# --------------------------------------------------------------------------
# palette_mocha_red() — id "mocha-red" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_mocha_red() {
PALETTE_ID="mocha-red"
PALETTE_NAME="Catppuccin Mocha (Red)"
PALETTE_SHORT="CatppuccinRed"
PALETTE_DESC="Catppuccin Mocha with the classic red accent — matches the stock catppuccin/kde Konsole theme."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=1e1e2e
C_MANTLE=181825
C_CRUST=11111b
C_SURFACE0=313244
C_SURFACE1=45475a
C_OVERLAY0=6c7086
C_OVERLAY1=7f849c
C_TEXT=cdd6f4
C_SUBTEXT0=a6adc8
C_SUBTEXT1=bac2de

C_ACCENT=f38ba8
C_ACCENT_FG=1e1e2e
C_ACCENT_DIM=f9b6c8

C_0=45475a
C_1=f38ba8
C_2=a6e3a1
C_3=f9e2af
C_4=89b4fa
C_5=f5c2e7
C_6=94e2d5
C_7=bac2de
C_8=585b70
C_9=f38ba8
C_10=a6e3a1
C_11=f9e2af
C_12=89b4fa
C_13=f5c2e7
C_14=94e2d5
C_15=a6adc8
}

# --------------------------------------------------------------------------
# palette_nord() — id "nord" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_nord() {
PALETTE_ID="nord"
PALETTE_NAME="Nord"
PALETTE_SHORT="Nord"
PALETTE_DESC="Arctic, bluish cold palette (nordicy)."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=2e3440
C_MANTLE=2e3440
C_CRUST=242933
C_SURFACE0=3b4252
C_SURFACE1=434c5e
C_OVERLAY0=616e88
C_OVERLAY1=7b88a1
C_TEXT=eceff4
C_SUBTEXT0=d8dee9
C_SUBTEXT1=e5e9f0

C_ACCENT=88c0d0
C_ACCENT_FG=2e3440
C_ACCENT_DIM=9cd4e0

C_0=3b4252
C_1=bf616a
C_2=a3be8c
C_3=ebcb8b
C_4=81a1c1
C_5=b48ead
C_6=88c0d0
C_7=e5e9f0
C_8=4c566a
C_9=bf616a
C_10=a3be8c
C_11=ebcb8b
C_12=81a1c1
C_13=b48ead
C_14=8fbcbb
C_15=eceff4
}

# --------------------------------------------------------------------------
# palette_otto() — id "otto" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_otto() {
# OttoRed — muted-spectrum red/black palette.
#
# Modelled on the Otto Plasma theme by App-walled (store.kde.org/p/1358262/):
# an almost-black neutral ramp carrying one saturated red, with the ANSI
# range deliberately desaturated so nothing in the terminal out-shouts the
# accent. Kept as a first-class palette (not a special case in the engine)
# so it gets the same Konsole scheme, .colors file, Global Theme and
# cursor handling as every other palette here.
#
# The companion graphical bits of the Otto theme (Global Theme package,
# Kvantum, window decoration) are NOT shipped in this repo: they are
# installed once through the KDE GUI (store.kde.org is behind Anubis, so
# a scripted download is not an option), and scripts/lib/otto.sh picks
# them up when present and recolours them to match these values.
PALETTE_ID="otto"
PALETTE_NAME="Otto Red"
PALETTE_SHORT="OttoRed"
PALETTE_DESC="Otto-inspired muted-spectrum red/black — near-black surfaces, one saturated red accent, desaturated ANSI range."

# Same reasoning as every other palette here: an id that is not installed
# yields no cursor at all rather than a fallback, so this stays optional and
# resolve_cursor_theme is left to decide what to do when it is missing.
CURSOR_THEME="Bibata-Modern-Ice"

# --- surfaces ---------------------------------------------------------------
C_BG=0e0e11
C_MANTLE=141417
C_CRUST=08080a
C_SURFACE0=1b1b1f
C_SURFACE1=232327
C_OVERLAY0=2b2b30
C_OVERLAY1=35353b

# --- text -------------------------------------------------------------------
# Not pure white: full #ffffff on a #0e0e11 field is the harsh, blue-sorted
# look Otto specifically avoids. eaeaea reads as white while keeping the red
# accent as the brightest thing on screen.
C_TEXT=eaeaea
C_SUBTEXT0=b8b8bd
C_SUBTEXT1=8b8b92

# --- accent -----------------------------------------------------------------
C_ACCENT=e5484d
C_ACCENT_FG=0e0e11
C_ACCENT_DIM=7a2226

# --- ANSI 16 ----------------------------------------------------------------
# Black row is lifted just clear of the surfaces so a black-on-black prompt is
# never invisible; the whole 4-7 / 12-15 range is desaturated toward the
# neutrals, which is what keeps this "muted" rather than neon.
C_0=141417
C_1=e5484d
C_2=6f9c86
C_3=c9a26d
C_4=7b93b8
C_5=b08bb0
C_6=7aa07f
C_7=c4c4ca
C_8=35353b
C_9=f26469
C_10=8ab5a0
C_11=e0b98a
C_12=9db2d4
C_13=c7a3c7
C_14=96b79a
C_15=f2f2f5
}

# --------------------------------------------------------------------------
# palette_solarized() — id "solarized" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_solarized() {
PALETTE_ID="solarized"
PALETTE_NAME="Solarized Dark"
PALETTE_SHORT="SolarizedDark"
PALETTE_DESC="Solarized dark — the precision color scheme, cyan-blue accent."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=002b36
C_MANTLE=073642
C_CRUST=00212b
C_SURFACE0=073642
C_SURFACE1=0a3948
C_OVERLAY0=586e75
C_OVERLAY1=657b83
C_TEXT=839496
C_SUBTEXT0=586e75
C_SUBTEXT1=657b83

C_ACCENT=268bd2
C_ACCENT_FG=002b36
C_ACCENT_DIM=4ba7e0

C_0=073642
C_1=dc322f
C_2=859900
C_3=b58900
C_4=268bd2
C_5=d33682
C_6=2aa198
C_7=eee8d5
C_8=002b36
C_9=cb4b16
C_10=586e75
C_11=657b83
C_12=839496
C_13=6c71c4
C_14=93a1a1
C_15=fdf6e3
}

# --------------------------------------------------------------------------
# palette_tokyo_night() — id "tokyo-night" (the - is _ in the function name:
# bash cannot CALL a function with a hyphen in its name, only define one.)
# --------------------------------------------------------------------------
palette_tokyo_night() {
PALETTE_ID="tokyo-night"
PALETTE_NAME="Tokyo Night"
PALETTE_SHORT="TokyoNight"
PALETTE_DESC="Tokyo Night — deep storm blues with bright terminal accents."

# Cursor theme for this palette. Bibata Modern Ice is a white/neutral
# Material cursor, which stays legible on every dark background in this
# kit. Left optional on purpose: an id that is not installed yields NO
# cursor rather than a fallback, so an unset value must mean "leave the
# cursor alone", never "assume a default".
CURSOR_THEME="Bibata-Modern-Ice"

C_BG=1a1b26
C_MANTLE=16161e
C_CRUST=16161e
C_SURFACE0=24283b
C_SURFACE1=2f3549
C_OVERLAY0=565f89
C_OVERLAY1=62688f
C_TEXT=c0caf5
C_SUBTEXT0=a9b1d6
C_SUBTEXT1=b4b8d6

C_ACCENT=7aa2f7
C_ACCENT_FG=1a1b26
C_ACCENT_DIM=a0b6fc

C_0=15161e
C_1=f7768e
C_2=9ece6a
C_3=e0af68
C_4=7aa2f7
C_5=bb9af7
C_6=7dcfff
C_7=a9b1d6
C_8=414868
C_9=f7768e
C_10=9ece6a
C_11=e0af68
C_12=7aa2f7
C_13=bb9af7
C_14=7dcfff
C_15=c0caf5
}

# ---------------------------------------------------------------------------
# palette_moe_dark() -- id "moe-dark"
#
# Colors are upstream's, not taste: Moe v2.6 by jomada, whose Plasma color
# scheme (MoeDark.colors) and Konsole scheme (MoeDark.colorscheme) are the
# published source of truth. Every value below is transcribed from those two
# files, so the toolkit's generated scheme agrees with the real theme instead of
# merely resembling it.
#
# Surfaces, from MoeDark.colors and MoeDark.colorscheme [Background*]:
#   normal 38,41,46 #26292e | faint 46,50,56 #2e3238 | intense 32,34,39 #202227
# Button background #2f343a sits between the surface and the faint shade, which
# is why it is used here rather than one of the three above.
# ---------------------------------------------------------------------------
palette_moe_dark() {
PALETTE_ID="moe-dark"
PALETTE_NAME="Moe Dark"
PALETTE_SHORT="MoeDark"
PALETTE_DESC="Moe Dark -- the Moe v2.6 theme's own palette: #26292e grey with the #ff6376 pink-red accent and a cyan #2bb1af."

# Optional on purpose: an id that is not installed yields NO cursor rather than
# a fallback (see resolve_cursor_theme). Moe ships no cursor of its own.
CURSOR_THEME="Bibata-Modern-Ice"

# Surfaces
C_BG=26292e
C_MANTLE=2e3238
C_CRUST=202227
C_SURFACE0=2e3238
C_SURFACE1=2f343a
C_OVERLAY0=3f454d
C_OVERLAY1=4c525a

# Text. MoeDark.colors ForegroundNormal is 252,252,252 (#fcfcfc); the Konsole
# scheme's own Foreground is a dimmer 189,195,199 (#bdc3c7), kept below as
# C_SUBTEXT0's neighbour. Upstream has no single "subtle" value, so
# C_SUBTEXT0 is the Konsole Foreground and C_SUBTEXT1 the .colors
# ForegroundInactive (160,160,160).
C_TEXT=fcfcfc
C_SUBTEXT0=bdc3c7
C_SUBTEXT1=a0a0a0

# Accent = MoeDark.colors [Colors:Selection] BackgroundNormal 255,99,118. The
# bright variant of the same hue is Konsole Color4 (255,98,119), a different red
# one unit away, which is why C_ACCENT_DIM is the .colors link blue instead of
# a dimmed accent: there is no upstream dimmed accent to copy.
C_ACCENT=ff6376
C_ACCENT_FG=000000
C_ACCENT_DIM=3daee9

# ANSI, verbatim from MoeDark.colorscheme Color0..Color7.
C_0=a36751
C_1=ff597d
C_2=2bb1af
C_3=39abdc
C_4=ff6277
C_5=c679dd
C_6=ffe185
C_7=9cacad

# The bright eight are DERIVED, not copied: MoeDark.colorscheme stops at
# Color7. Each C_n+8 is that color's own [ColorNFaint] variant -- what Konsole
# itself uses when a scheme ships only eight colors -- so `bold` renders as a
# lighter shade of the same hue rather than as a duplicate of the normal one.
# Blank black/white would have been the other choice and is worse: bright black
# on a #26292e background is invisible.
C_8=ba765d
C_9=ff658e
C_10=2cb5b3
C_11=3bb4e8
C_12=ff6378
C_13=cd85e4
C_14=ffe8a3
C_15=a5b5b6
}
