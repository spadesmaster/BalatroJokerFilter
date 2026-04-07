# Joker Filter submission checklist

## Steamodded package
Make sure your shipped mod folder contains:

```text
JokerFilter/
  joker_filter.json
  config.lua
  main.lua
  assets/
    1x/
      joker_filter.png
    2x/
      joker_filter.png
```

## Steamodded metadata
Verify:
- `main_file` matches `main.lua`
- `icon_path` matches `joker_filter.png`
- icon exists in both `assets/1x` and `assets/2x`
- `dependencies` includes:
  - `Steamodded (>=1.0.0~BETA-1606b)`
  - `cartomancer`
- version in `joker_filter.json` matches the release you are shipping

## GitHub repo / release
Before submission:
- push the current code to GitHub
- create a release
- attach a downloadable archive (zip is typical)
- make sure the archive expands to a single `JokerFilter` folder
- make sure the `downloadURL` points to the direct downloadable asset, not the HTML release page

## Balatro Mod Index / Mod Manager
For Mod Manager indexing you need a separate submission folder with:
- `description.md`
- `meta.json`
- optional `thumbnail.jpg` (JPEG only)

Recommended structure for the Mod Index PR:

```text
mods/
  BigRed@JokerFilter/
    description.md
    meta.json
    thumbnail.jpg   # optional
```

## Recommended extras
Not strictly required, but helpful:
- `README.md` in your repo root
- at least one screenshot or short gif in the repo README
- a license file
- changelog or release notes
