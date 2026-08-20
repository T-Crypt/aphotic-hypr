-- Nvidia-specific environment variables
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
-- and the ArchWiki hardware acceleration page before changing these values.

hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("LIBVA_DRIVER_NAME", "nvidia")

-- The following may cause issues — proceed with care, see the ArchWiki Wayland page.
-- hl.env("GBM_BACKEND", "nvidia-drm")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("__GL_GSYNC_ALLOWED", "")
-- hl.env("__GL_VRR_ALLOWED", "")
-- hl.env("WLR_DRM_NO_ATOMIC", "1")
