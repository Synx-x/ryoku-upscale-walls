# Changelog

## 0.1.2

- The bar glyph shows only on demand. It appears while an upscale runs and stays for a set time after the result.

## 0.1.1

- Fix: a finished upscale no longer replaces a wallpaper you picked while it was processing. It is cached and marked ready instead.
- The bar glyph pulses and the panel names the file while an upscale runs.
- A desktop notification announces the start, the result, a failure, or a result that was not applied.

## 0.1.0

First release.

- Upscales a small wallpaper on the GPU when it is picked, then applies the larger copy.
- Real-ESRGAN and waifu2x engines, with Auto mode.
- Result cache with a size limit. The original file is never modified.
- Bar glyph and panel with Show original and Upscale again.
