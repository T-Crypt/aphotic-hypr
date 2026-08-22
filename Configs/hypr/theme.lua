-- Environment variables — see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "20")

-- QT_QPA_PLATFORMTHEME covers Qt5 apps; without the _QT6 variant, Qt6 apps
-- silently fell back to it too instead of reading their own qt6ct config
-- (Configs/qt6ct/qt6ct.conf existed but nothing ever pointed Qt6 apps at
-- it -- found during a Configs/ cleanup pass).
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_QPA_PLATFORMTHEME_QT6", "qt6ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
