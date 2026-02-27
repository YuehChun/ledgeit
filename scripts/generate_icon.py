#!/usr/bin/env python3
"""
LedgeIt App Icon Generator
Generates a glossy open ledger book icon in macOS style.
Renders at 4x resolution and downscales for anti-aliasing.
"""

import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

# Render at 4x for anti-aliasing
RENDER_SIZE = 4096
FINAL_SIZE = 1024


def lerp_color(c1, c2, t):
    """Linear interpolate between two RGB(A) colors."""
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def create_gradient(size, c1, c2, direction="vertical"):
    """Create a gradient image."""
    img = Image.new("RGBA", size)
    pixels = img.load()
    w, h = size
    for y in range(h):
        for x in range(w):
            if direction == "vertical":
                t = y / h
            elif direction == "horizontal":
                t = x / w
            else:  # diagonal
                t = (x / w + y / h) / 2
            color = lerp_color(c1, c2, t)
            pixels[x, y] = color
    return img


def draw_rounded_rect(draw, bbox, radius, fill):
    """Draw a rounded rectangle."""
    x1, y1, x2, y2 = bbox
    draw.rounded_rectangle(bbox, radius=radius, fill=fill)


def create_squircle_mask(size, padding=0):
    """Create a macOS-style squircle (superellipse) mask."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    # macOS uses a continuous curvature corner radius of ~22.37% of icon size
    radius = int(size * 0.2237)
    p = padding
    draw.rounded_rectangle(
        [p, p, size - 1 - p, size - 1 - p],
        radius=radius,
        fill=255,
    )
    return mask


def draw_polygon_aa(canvas, points, fill):
    """Draw a filled polygon onto the canvas."""
    draw = ImageDraw.Draw(canvas)
    draw.polygon(points, fill=fill)


def apply_gradient_to_polygon(canvas, points, c1, c2, bbox=None):
    """Fill a polygon with a vertical gradient."""
    if bbox is None:
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        bbox = (min(xs), min(ys), max(xs), max(ys))

    x1, y1, x2, y2 = bbox
    w, h = x2 - x1, y2 - y1
    if w <= 0 or h <= 0:
        return

    # Create gradient
    grad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grad_pixels = grad.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        color = lerp_color(c1, c2, t)
        for x in range(w):
            grad_pixels[x, y] = color

    # Create mask from polygon
    mask = Image.new("L", canvas.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.polygon(points, fill=255)

    # Paste gradient using mask
    grad_full = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    grad_full.paste(grad, (x1, y1))

    canvas.paste(Image.composite(grad_full, canvas, mask), (0, 0))


def generate_icon():
    S = RENDER_SIZE
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # === 1. Background squircle with gradient ===
    bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg_gradient = create_gradient(
        (S, S),
        (42, 74, 140, 255),    # #2A4A8C top
        (20, 35, 68, 255),     # #142344 bottom
    )
    mask = create_squircle_mask(S)
    bg.paste(bg_gradient, (0, 0), mask)
    canvas = Image.alpha_composite(canvas, bg)

    # === 2. Subtle radial highlight on background ===
    highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(highlight)
    cx, cy = int(S * 0.35), int(S * 0.3)
    for r in range(int(S * 0.5), 0, -2):
        alpha = int(25 * (1 - r / (S * 0.5)))
        h_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(100, 140, 220, max(0, alpha)),
        )
    canvas = Image.alpha_composite(canvas, Image.composite(highlight, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    draw = ImageDraw.Draw(canvas)

    # === 3. Book shadow ===
    shadow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)
    # Shadow polygon (offset down and right from book)
    shadow_points = [
        (int(S * 0.16), int(S * 0.28)),
        (int(S * 0.52), int(S * 0.22)),
        (int(S * 0.88), int(S * 0.28)),
        (int(S * 0.86), int(S * 0.82)),
        (int(S * 0.52), int(S * 0.86)),
        (int(S * 0.18), int(S * 0.82)),
    ]
    # Offset shadow
    shadow_offset = int(S * 0.02)
    shadow_points_offset = [(x + shadow_offset, y + shadow_offset) for x, y in shadow_points]
    s_draw.polygon(shadow_points_offset, fill=(0, 0, 0, 80))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=int(S * 0.025)))
    canvas = Image.alpha_composite(canvas, Image.composite(shadow_layer, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # === 4. Define book geometry ===
    # The book is open, viewed from slightly above
    # Left side = back cover (dark blue), Right side = open pages (cream)
    # Spine is in the middle

    spine_x = int(S * 0.48)  # Spine slightly left of center

    # Back cover (left side) - dark navy leather
    cover_tl = (int(S * 0.15), int(S * 0.26))
    cover_tr = (spine_x, int(S * 0.21))
    cover_br = (spine_x, int(S * 0.79))
    cover_bl = (int(S * 0.17), int(S * 0.80))

    # Open pages (right side) - cream/white
    pages_tl = (spine_x + int(S * 0.008), int(S * 0.21))
    pages_tr = (int(S * 0.85), int(S * 0.27))
    pages_br = (int(S * 0.83), int(S * 0.81))
    pages_bl = (spine_x + int(S * 0.008), int(S * 0.79))

    # Book thickness (bottom edge - visible due to perspective)
    thickness = int(S * 0.025)

    # === 5. Draw book thickness (gold page edges) ===
    # Bottom edge of pages (gold)
    page_edge_points = [
        pages_bl,
        pages_br,
        (pages_br[0] + int(S * 0.005), pages_br[1] + thickness),
        (pages_bl[0], pages_bl[1] + thickness),
    ]
    apply_gradient_to_polygon(canvas, page_edge_points,
                              (212, 168, 67, 255),   # #D4A843
                              (180, 140, 50, 255))    # darker gold

    # Right edge of pages (gold)
    right_edge_points = [
        pages_tr,
        (pages_tr[0] + int(S * 0.005), pages_tr[1] + thickness),
        (pages_br[0] + int(S * 0.005), pages_br[1] + thickness),
        pages_br,
    ]
    apply_gradient_to_polygon(canvas, right_edge_points,
                              (240, 214, 138, 255),  # #F0D68A lighter gold
                              (190, 155, 60, 255))   # darker gold

    # Bottom edge of cover
    cover_edge_points = [
        cover_bl,
        cover_br,
        (cover_br[0], cover_br[1] + thickness),
        (cover_bl[0] + int(S * 0.005), cover_bl[1] + thickness),
    ]
    apply_gradient_to_polygon(canvas, cover_edge_points,
                              (15, 25, 55, 255),   # very dark navy
                              (10, 18, 40, 255))

    # Left edge of cover
    left_edge_points = [
        cover_tl,
        cover_bl,
        (cover_bl[0] - int(S * 0.005), cover_bl[1] + thickness),
        (cover_tl[0] - int(S * 0.005), cover_tl[1] + thickness),
    ]
    apply_gradient_to_polygon(canvas, left_edge_points,
                              (18, 30, 60, 255),
                              (10, 18, 40, 255))

    # === 6. Draw back cover (dark navy) ===
    cover_points = [cover_tl, cover_tr, cover_br, cover_bl]
    apply_gradient_to_polygon(canvas, cover_points,
                              (26, 39, 68, 255),    # #1A2744 top
                              (16, 28, 55, 255))    # slightly darker bottom

    # === 7. Cover leather texture (subtle noise overlay) ===
    # Glossy highlight on cover (top-left area)
    cover_highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ch_draw = ImageDraw.Draw(cover_highlight)
    # Elliptical highlight
    hx1 = int(S * 0.18)
    hy1 = int(S * 0.28)
    hx2 = int(S * 0.42)
    hy2 = int(S * 0.50)
    for i in range(40):
        t = i / 40
        alpha = int(35 * (1 - t))
        shrink = int(t * (hx2 - hx1) * 0.3)
        ch_draw.ellipse(
            [hx1 + shrink, hy1 + shrink, hx2 - shrink, hy2 - shrink],
            fill=(80, 110, 180, max(0, alpha)),
        )
    cover_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(cover_mask).polygon(cover_points, fill=255)
    cover_highlight_masked = Image.composite(
        cover_highlight,
        Image.new("RGBA", (S, S), (0, 0, 0, 0)),
        cover_mask,
    )
    canvas = Image.alpha_composite(canvas, cover_highlight_masked)

    # === 8. Gold border/trim on cover ===
    draw = ImageDraw.Draw(canvas)
    # Inner gold frame on cover
    inset = int(S * 0.025)
    inner_cover = [
        (cover_tl[0] + inset, cover_tl[1] + inset),
        (cover_tr[0] - inset // 2, cover_tr[1] + inset),
        (cover_br[0] - inset // 2, cover_br[1] - inset),
        (cover_bl[0] + inset, cover_bl[1] - inset),
    ]
    draw.line(
        inner_cover + [inner_cover[0]],
        fill=(212, 168, 67, 120),  # semi-transparent gold
        width=int(S * 0.004),
    )

    # === 9. Draw open pages (cream/off-white) ===
    pages_points = [pages_tl, pages_tr, pages_br, pages_bl]
    apply_gradient_to_polygon(canvas, pages_points,
                              (255, 248, 237, 255),  # #FFF8ED top
                              (242, 235, 220, 255))  # #F2EBDC bottom

    # === 10. Shadow near spine on pages ===
    spine_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ss_draw = ImageDraw.Draw(spine_shadow)
    shadow_width = int(S * 0.06)
    spine_shadow_points = [
        pages_tl,
        (pages_tl[0] + shadow_width, pages_tl[1] + int(S * 0.01)),
        (pages_bl[0] + shadow_width, pages_bl[1] - int(S * 0.01)),
        pages_bl,
    ]
    for i in range(20):
        t = i / 20
        alpha = int(50 * (1 - t))
        offset = int(t * shadow_width)
        pts = [
            (pages_tl[0] + offset, pages_tl[1]),
            (pages_tl[0] + shadow_width, pages_tl[1] + int(S * 0.01)),
            (pages_bl[0] + shadow_width, pages_bl[1] - int(S * 0.01)),
            (pages_bl[0] + offset, pages_bl[1]),
        ]
        ss_draw.polygon(pts, fill=(30, 25, 15, max(0, alpha)))

    pages_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(pages_mask).polygon(pages_points, fill=255)
    spine_shadow_masked = Image.composite(
        spine_shadow,
        Image.new("RGBA", (S, S), (0, 0, 0, 0)),
        pages_mask,
    )
    canvas = Image.alpha_composite(canvas, spine_shadow_masked)

    # === 11. Transaction lines on pages ===
    draw = ImageDraw.Draw(canvas)
    num_lines = 8
    page_top_y = pages_tl[1] + int(S * 0.06)
    page_bot_y = pages_br[1] - int(S * 0.06)
    line_spacing = (page_bot_y - page_top_y) // (num_lines + 1)

    for i in range(1, num_lines + 1):
        y = page_top_y + i * line_spacing
        # Calculate x positions at this y (interpolate along page edges)
        t = (y - pages_tl[1]) / (pages_bl[1] - pages_tl[1])
        x_left = pages_tl[0] + (pages_bl[0] - pages_tl[0]) * t + int(S * 0.07)
        x_right = pages_tr[0] + (pages_br[0] - pages_tr[0]) * t - int(S * 0.03)

        # Faint gold transaction lines
        draw.line(
            [(int(x_left), y), (int(x_right), y)],
            fill=(196, 154, 60, 45),  # #C49A3C at ~18% opacity
            width=int(S * 0.003),
        )

    # Draw a couple of "amount" marks (short lines at right side)
    for i in [2, 4, 6]:
        y = page_top_y + i * line_spacing
        t = (y - pages_tl[1]) / (pages_bl[1] - pages_tl[1])
        x_right = pages_tr[0] + (pages_br[0] - pages_tr[0]) * t - int(S * 0.03)
        x_amt = x_right - int(S * 0.08)
        draw.line(
            [(x_amt, y - int(S * 0.008)), (x_amt, y + int(S * 0.008))],
            fill=(196, 154, 60, 55),
            width=int(S * 0.003),
        )

    # === 12. Red margin line on pages ===
    margin_offset = int(S * 0.12)
    margin_top_y = pages_tl[1] + int(S * 0.03)
    margin_bot_y = pages_bl[1] - int(S * 0.03)
    t_top = (margin_top_y - pages_tl[1]) / (pages_bl[1] - pages_tl[1])
    t_bot = (margin_bot_y - pages_tl[1]) / (pages_bl[1] - pages_tl[1])
    margin_x_top = pages_tl[0] + (pages_bl[0] - pages_tl[0]) * t_top + margin_offset
    margin_x_bot = pages_tl[0] + (pages_bl[0] - pages_tl[0]) * t_bot + margin_offset
    draw.line(
        [(int(margin_x_top), margin_top_y), (int(margin_x_bot), margin_bot_y)],
        fill=(200, 80, 80, 60),  # faint red
        width=int(S * 0.003),
    )

    # === 13. Spine detail ===
    spine_width = int(S * 0.012)
    spine_points = [
        (spine_x - spine_width, cover_tr[1]),
        (spine_x + spine_width, pages_tl[1]),
        (spine_x + spine_width, pages_bl[1]),
        (spine_x - spine_width, cover_br[1]),
    ]
    apply_gradient_to_polygon(canvas, spine_points,
                              (12, 20, 42, 255),    # very dark navy
                              (8, 14, 32, 255))

    # Spine highlight (thin bright line)
    draw = ImageDraw.Draw(canvas)
    draw.line(
        [(spine_x + spine_width + 1, pages_tl[1] + int(S * 0.02)),
         (spine_x + spine_width + 1, pages_bl[1] - int(S * 0.02))],
        fill=(60, 80, 120, 80),
        width=int(S * 0.003),
    )

    # === 14. Page curl effect (subtle highlight on top-right of pages) ===
    page_highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ph_draw = ImageDraw.Draw(page_highlight)
    # Light reflection on pages
    for i in range(30):
        t = i / 30
        alpha = int(30 * (1 - t))
        w = int(S * 0.15 * (1 - t))
        h = int(S * 0.08 * (1 - t))
        cx = int(S * 0.72)
        cy = int(S * 0.32)
        ph_draw.ellipse(
            [cx - w, cy - h, cx + w, cy + h],
            fill=(255, 255, 255, max(0, alpha)),
        )
    canvas = Image.alpha_composite(canvas, Image.composite(
        page_highlight,
        Image.new("RGBA", (S, S), (0, 0, 0, 0)),
        pages_mask,
    ))

    # === 15. Overall vignette on the squircle ===
    vignette = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    v_draw = ImageDraw.Draw(vignette)
    for i in range(50):
        t = i / 50
        alpha = int(20 * t)
        border = int(S * 0.5 * (1 - t))
        v_draw.rounded_rectangle(
            [border, border, S - border, S - border],
            radius=int(S * 0.2237 * (1 - t * 0.5)),
            outline=(0, 0, 10, max(0, alpha)),
            width=int(S * 0.01),
        )

    # === 16. Apply squircle mask to final result ===
    final = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    final.paste(canvas, (0, 0), mask)

    # Downscale to 1024x1024 with high-quality resampling
    final = final.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)

    return final


def generate_all_sizes(icon_1024, output_dir):
    """Generate all macOS icon sizes."""
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    for filename, size in sizes.items():
        resized = icon_1024.resize((size, size), Image.LANCZOS)
        path = f"{output_dir}/{filename}"
        resized.save(path, "PNG")
        print(f"  Generated {filename} ({size}x{size})")


if __name__ == "__main__":
    import os

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    output_dir = os.path.join(
        project_root,
        "LedgeIt", "LedgeIt", "Assets.xcassets", "AppIcon.appiconset",
    )

    print("Generating LedgeIt app icon...")
    icon = generate_icon()

    # Save 1024 master
    master_path = os.path.join(output_dir, "icon_master_1024.png")
    icon.save(master_path, "PNG")
    print(f"  Saved master icon: {master_path}")

    # Generate all sizes
    print("Generating all macOS icon sizes...")
    generate_all_sizes(icon, output_dir)

    print("\nDone! Icon files saved to:")
    print(f"  {output_dir}")
