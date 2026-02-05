---
name: favicon
description: Generate a complete set of favicons from a source image and update HTML. Use when setting up favicons for a web project.
argument-hint: [path to source image]
---

# Favicon Generator

Generate a complete set of favicons from the source image at `$1` and update the project's HTML with the appropriate link tags.

## Prerequisites

First, verify ImageMagick v7+ is installed:
```bash
which magick
```

If not found, install it:
- **macOS**: `brew install imagemagick`
- **Linux**: `sudo apt install imagemagick`

## Step 1: Validate Source Image

1. Verify the source image exists at the provided path: `$1`
2. Check the file extension is supported (PNG, JPG, JPEG, SVG, WEBP, GIF)
3. Note if the source is SVG (will also be copied as favicon.svg)

## Step 2: Detect Project Type

| Framework | Detection | Static Assets Directory |
|-----------|-----------|------------------------|
| Next.js | `next.config.*` | `public/` |
| Vite | `vite.config.*` | `public/` |
| Rails | `config/routes.rb` | `public/` |
| Static HTML | `index.html` in root | Same as index.html |

## Step 3: Generate Favicon Files

```bash
# favicon.ico (multi-resolution: 16x16, 32x32, 48x48)
magick "$1" \
  \( -clone 0 -resize 16x16 \) \
  \( -clone 0 -resize 32x32 \) \
  \( -clone 0 -resize 48x48 \) \
  -delete 0 -alpha on -background none \
  [STATIC_DIR]/favicon.ico

# favicon-96x96.png
magick "$1" -resize 96x96 -background none -alpha on [STATIC_DIR]/favicon-96x96.png

# apple-touch-icon.png (180x180)
magick "$1" -resize 180x180 -background none -alpha on [STATIC_DIR]/apple-touch-icon.png

# web-app-manifest-192x192.png
magick "$1" -resize 192x192 -background none -alpha on [STATIC_DIR]/web-app-manifest-192x192.png

# web-app-manifest-512x512.png
magick "$1" -resize 512x512 -background none -alpha on [STATIC_DIR]/web-app-manifest-512x512.png

# favicon.svg (only if source is SVG)
cp "$1" [STATIC_DIR]/favicon.svg
```

## Step 4: Create site.webmanifest

```json
{
  "name": "[APP_NAME]",
  "short_name": "[APP_NAME]",
  "icons": [
    { "src": "/web-app-manifest-192x192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "/web-app-manifest-512x512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "theme_color": "#ffffff",
  "background_color": "#ffffff",
  "display": "standalone"
}
```

## Step 5: Update HTML

Add to `<head>`:
```html
<link rel="icon" type="image/png" href="/favicon-96x96.png" sizes="96x96" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<link rel="shortcut icon" href="/favicon.ico" />
<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
<meta name="apple-mobile-web-app-title" content="[APP_NAME]" />
<link rel="manifest" href="/site.webmanifest" />
```

## Summary

Report:
- Detected project type
- Static assets directory used
- Files generated
- App name used
- Layout file updated
