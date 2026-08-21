import os
import argparse
import subprocess

ap = argparse.ArgumentParser()
ap.add_argument("-i", "--image", required=True, help="path to input image")
args = vars(ap.parse_args())

image_path = args["image"]
awww_dir = os.path.expanduser(os.environ.get("NOCTIS_AWWW_DIR", "~/.config/awww"))

# Change the wallpaper
subprocess.run(["awww", "img", "--transition-type", "wipe", "--transition-duration", "3", image_path])
# Generate the wallust colorscheme; templates write straight to their targets (see wallust.toml)
subprocess.run(["wallust", "run", image_path])
# generate wallpaper.rofi -- the shared "current wallpaper" marker, see
# services/Wallpapers.qml
subprocess.run(["cp", image_path, os.path.join(awww_dir, "wallpaper.rofi")])
# firefox
subprocess.run(["pywalfox", "update"])
# Reload the shell to apply colorscheme
subprocess.run(["noctis", "reload"])
# Send a notification
subprocess.run([
    "notify-send",
    "-h", "string:x-canonical-private-synchronous:hypr-cfg",
    "-u", "low",
    f"Wallpaper changed to {os.path.basename(image_path)}",
])
