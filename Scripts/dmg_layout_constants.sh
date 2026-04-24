# Synchron mit Scripts/RenderDMGBackground.swift (W, H, logoW, logoH, arrowHalf, iconGap, iconSize).
#
# Geometrie 400×200: Footer-Logo 126×34, Rand unten 10 → logoTop, bandBottom, Pfeilmitte wie im Renderer.
# Icon-Mitten X: 82 / 318 (arrowHalf=54). DMG_ICON_Y: für create-dmg/Finder kalibriert (70), nicht zwingend
# gleich dem theoretischen iconYFinder aus RenderDMGBackground.swift — vertikal so belassen, wie es optisch passt.
#
# create-dmg: --window-size = Außenmaß; bei Änderung der PNG-Geometrie zuerst RenderDMGBackground.swift, dann diese Werte.

DMG_BG_LAYOUT_W=400
DMG_BG_LAYOUT_H=200
DMG_WINDOW_W=400
DMG_WINDOW_H=200
DMG_ICON_X=82
DMG_ICON_Y=70
DMG_DROP_X=318
