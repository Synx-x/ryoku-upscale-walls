# Changelog

## 0.2.4

- Fix: the orb now pulses from 95 percent, and during the final resize. The engine often stalls at about 97 percent while its last tile runs, so a 99 percent rule never fired.

## 0.2.3

- Fix: the orb no longer blinks out for a moment when an upscale finishes. It hides only after three status reads agree that no flip is available.

## 0.2.2

- The orb no longer shows a percentage. The ring and the orbiting spark show progress, and the orb pulses once it reaches 99 percent until the result lands.

## 0.2.1

- Fix: the orb now shows on every monitor's bar during an upscale. Each bar runs its own copy of the service, and only the one that started the job knew it was working. All copies now read the shared status file.

## 0.2.0

- The bar glyph is now an animated orb. It pulses with a progress ring and an orbiting spark while an upscale runs.
- The orb stays while the current wallpaper has an original and an upscaled copy. Filled means upscaled, hollow means original. Click it to flip between them instantly.
- The hover card previews the source image while processing, then shows the original and upscaled copies side by side.
- Removed the glyph linger setting. The orb now follows whether a flip is available.

## 0.1.3

- Real progress: the bar glyph shows the percentage with a progress strip while an upscale runs.
- Hover the glyph to open a details card with file, engine, size, elapsed time and time remaining. Click to pin it.

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
