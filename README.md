<img width="850" height="658" alt="image" src="https://github.com/user-attachments/assets/4841d59c-aa07-40a9-84f2-20b0bc860873" />


# BetterBetterBlizzPlates

A clean options window for BetterBlizzPlates. Does not edit its files.

## Use

`/bbbp` opens the window. So does the **Better Settings** button in the title bar of the Settings window, on any BetterBlizzPlates page.

### Pages

Settings are sorted by what they change, not by where BetterBlizzPlates put them:

Nameplates, Size and stacking, Names and text, Colors, Castbar, Auras, Indicators, Personal bar, System, Other.

- Each feature has one group. Its on/off switch is in the group header, next to its settings.
- Indicators opens folded: a list of features with their switches. Click a group to open it.
- **Fold all** / **Unfold all** for the page.
- Search finds a setting on any page.

### Preview

- **Preview** in a group header turns on that feature's test mode, so it shows on nameplates.
- Indicators, Auras and Size and stacking have a **Preview** for the whole page.
- A preview stays on when you close the window. A small bar on screen has **Stop**.
- Hold a slider: the window fades so you see the nameplates behind it.

### Controls

- Checkbox sits next to its label. Click anywhere on the row.
- Slider: **-** and **+** for one step, a box for the exact value. **Reset** where BetterBlizzPlates has a default for it.
- Dropdown shows the current choice. Texture lists show the bar, font lists use the font. Lists with several switches show how many are on.
- **More** opens the extra options that were hidden behind a right-click.
- A greyed setting says what it needs.

**Reload UI** reloads and opens this window again. It also comes back after `/reload` or BetterBlizzPlates' own reload prompt. Each page remembers where you scrolled.

**Original settings** opens BetterBlizzPlates' own window. Lists, profiles, import and export stay there.

Every control drives the real BetterBlizzPlates control, so settings behave the same.

If BetterBlizzPlates changes, unknown settings show on the Other page, or the window falls back to BetterBlizzPlates' own pages. Nothing breaks.

## Versions

Each release is made for one BetterBlizzPlates version. The version says which: `2.2.3f-p0` is for BetterBlizzPlates 2.2.3f. `p0`, `p1`, ... count our own updates for that version.

With any other BetterBlizzPlates version the window stays closed and says which version it needs.

## Game versions

Works on every game version BetterBlizzPlates supports: Retail, Forever, Mists, Cata, Wrath, TBC and Classic Era. One download for all.

Mists and older have fewer settings, because BetterBlizzPlates has fewer there.

## Install

Copy the folder to `Interface\AddOns\BetterBetterBlizzPlates` of your game version. Needs BetterBlizzPlates in the matching version.

## Release tools

`luajit tools/check.lua <path to BetterBlizzPlates>` - parses every file, checks the versions and the game version list, runs the tests for every game version, and reports what changed since the last release (`tools/snapshots`). Add `--update` to save new snapshots.

`luajit tools/build.lua` - makes `out/BetterBetterBlizzPlates-<version>.zip`. Refuses a `-dev` version unless `--dev` is given.

## Test

`luajit tests/test.lua <path to BetterBlizzPlates> [client]` - runs the window against BetterBlizzPlates' options code in a fake game API. Client: `forever` (default), `retail`, `era`, `tbc`, `wrath`, `cata`, `mists`.

`luajit tests/test_missing.lua` - checks nothing errors when BetterBlizzPlates is missing or changed.

`luajit tests/dump.lua <path to BetterBlizzPlates> [raw] [client]` - prints every setting by page and group. Add `raw` for BetterBlizzPlates' own pages.
