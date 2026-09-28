import os
import sys
import shutil
import subprocess
from PIL import Image, ImageFilter

def generate_icons(custom_source=None):
    src_path = None
    if custom_source and os.path.exists(custom_source):
        src_path = custom_source
    elif os.path.exists("Resources/Copak_raw.png"):
        src_path = "Resources/Copak_raw.png"
    elif os.path.exists("Resources/Copak.png"):
        src_path = "Resources/Copak.png"
    elif os.path.exists("Sources/ContextPacket/Resources/Copak.png"):
        src_path = "Sources/ContextPacket/Resources/Copak.png"

    if not src_path or not os.path.exists(src_path):
        print("No valid source icon found in repository. Skipping generation.")
        return

    print(f"Loading source icon from: {src_path}")
    orig = Image.open(src_path).convert('RGBA')

    # Standard macOS Big Sur+ Icon Grid:
    # Canvas: 1024 x 1024
    # Squircle: 824 x 824, centered at (100, 100)
    squircle_824 = orig.resize((824, 824), Image.Resampling.LANCZOS)
    alpha = squircle_824.split()[3]

    shadow_mask = Image.new('RGBA', (824, 824), (0, 0, 0, 255))
    shadow_mask.putalpha(alpha)

    # Directional shadow: offset y=+12, blur=18, opacity 0.20
    dir_canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    dir_canvas.paste(shadow_mask, (100, 112), shadow_mask)
    r, g, b, a = dir_canvas.split()
    a = a.point(lambda p: int(p * 0.20))
    dir_canvas.putalpha(a)
    dir_blurred = dir_canvas.filter(ImageFilter.GaussianBlur(radius=18))

    # Ambient shadow: offset y=+4, blur=8, opacity 0.15
    amb_canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    amb_canvas.paste(shadow_mask, (100, 104), shadow_mask)
    r, g, b, a = amb_canvas.split()
    a = a.point(lambda p: int(p * 0.15))
    amb_canvas.putalpha(a)
    amb_blurred = amb_canvas.filter(ImageFilter.GaussianBlur(radius=8))

    # Composite
    composite = Image.alpha_composite(dir_blurred, amb_blurred)
    composite.paste(squircle_824, (100, 100), squircle_824)

    # Clean zero-level noise
    r, g, b, a = composite.split()
    a = a.point(lambda p: 0 if p < 2 else p)
    composite.putalpha(a)

    # Save standardized 1024x1024 png
    os.makedirs("Resources", exist_ok=True)
    os.makedirs("Sources/ContextPacket/Resources", exist_ok=True)
    composite.save("Resources/Copak.png", format="PNG")
    composite.save("Sources/ContextPacket/Resources/Copak.png", format="PNG")
    print(f"Saved standardized 1024x1024 master icon to Resources/Copak.png. Bbox: {composite.getbbox()}")

    # Prepare iconset
    iconset_dir = "/tmp/Copak.iconset"
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [
        ("icon_16x16.png", (16, 16)),
        ("icon_16x16@2x.png", (32, 32)),
        ("icon_32x32.png", (32, 32)),
        ("icon_32x32@2x.png", (64, 64)),
        ("icon_128x128.png", (128, 128)),
        ("icon_128x128@2x.png", (256, 256)),
        ("icon_256x256.png", (256, 256)),
        ("icon_256x256@2x.png", (512, 512)),
        ("icon_512x512.png", (512, 512)),
        ("icon_512x512@2x.png", (1024, 1024)),
    ]

    for name, sz in sizes:
        img_resized = composite.resize(sz, Image.Resampling.LANCZOS)
        img_resized.save(os.path.join(iconset_dir, name), format="PNG")

    # Run iconutil
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", "Resources/AppIcon.icns"], check=True)
    shutil.copy("Resources/AppIcon.icns", "Sources/ContextPacket/Resources/AppIcon.icns")
    shutil.rmtree(iconset_dir)
    print("✓ Successfully generated Resources/AppIcon.icns and updated Sources/ContextPacket/Resources/AppIcon.icns")

if __name__ == "__main__":
    custom_src = None
    for i, arg in enumerate(sys.argv):
        if arg == "--source" and i + 1 < len(sys.argv):
            custom_src = sys.argv[i + 1]
        elif arg.endswith(".png") and os.path.exists(arg):
            custom_src = arg
    generate_icons(custom_src)
