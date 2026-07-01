# KOReader User Patches

A [KOReader](https://github.com/koreader/koreader) user patch that turns the
Skim dialog's bookmark buttons into **location‑history navigation**.

| Patch | Origin |
|---|---|
| [`2-skim-location-history.lua`](#2-skim-location-historylua--skim-location-history) | **Original** |

> Tested on KOReader **v2026.03** (Kindle). It should work on nearby versions,
> but the patch is tied to the version it was written against — see
> [Note on versioning](#note-on-versioning).

---

## What is a user patch?

A user patch is a `.lua` file that KOReader runs at startup to modify its own
behaviour, without you having to edit (or fork) KOReader itself. Patches live in
a `patches/` folder inside your KOReader directory and are applied
automatically.

The numeric prefix sets *when* a patch runs and the order patches run in
(natural sort, so `2-…` before `10-…`):

- `1-…` – early, before the UI is ready
- `2-…` – late, after the UI is ready (what this patch uses)
- `8-…` / `9-…` – just before / at exit

If a patch fails to load, KOReader shows an error popup at startup and you can
disable individual patches from **Menu → Tools (gear) → Patches**, so a broken
patch can never lock you out.

## Installation

1. Find your KOReader directory. On Kindle it is typically
   `/mnt/us/koreader/`; on other platforms it's wherever KOReader is installed
   (e.g. `~/.config/koreader/` on desktop Linux).
2. Create a `patches/` subfolder inside it if it doesn't already exist.
3. Copy `2-skim-location-history.lua` into `koreader/patches/`.
4. Restart KOReader.

---

## `2-skim-location-history.lua` — Skim location history

**Original work.** Repurposes the three "bookmark" buttons in the **Skim
dialog** (the page‑navigation popup, `skimtowidget.lua`) to navigate
**location history** instead of bookmarks, while preserving the original
bookmark actions on long‑press. Location history here is KOReader's own
back/forward link stack (the same one used by swipe‑back and "go back to
previous location"), so the buttons integrate with the rest of the reader.

### Button behaviour

| Button | Icon | Tap | Long‑press |
|---|---|---|---|
| (former *previous bookmark*) | ↺ | **Previous location** | Previous bookmark |
| (former *bookmark toggle*) | ⊕ | **Add current page to location history** | *mode‑dependent — see below* |
| (former *next bookmark*) | ↻ | **Next location** | Next bookmark |
| Page number (centre) | — | Go‑to‑page input | **Open page overview** (Book Map / Page Browser) |

- The **Previous / Next location** buttons are **greyed out and ignore taps**
  when there is nowhere to go back / forward to. Their **long‑press
  (previous / next bookmark) still works even while greyed**, so bookmark
  navigation is never blocked.
- The **page‑number long‑press opens a page‑overview widget in both layouts**.
  Which one is configurable (see below). Returning to the page you opened Skim
  from is still reachable via the Previous‑location button / location history.

### Full vs. compact layout

The remaining long‑press of the ⊕ button differs by layout so that no
functionality is lost:

- **Full (centred) Skim dialog:** ⊕ long‑press = **bookmark current page**
  (there's no separate bookmark button in this layout).
- **Compact (top/bottom) Skim dialog:** the old "return to opening page" button
  becomes a **dedicated bookmark button** (tap = bookmark current page,
  long‑press = open bookmarks), so the ⊕ long‑press is freed up to be
  **back to the page Skim was opened from**.

### Configuration

One option, clearly marked at the top of the file:

```lua
-- "bookmap"     -> Book Map
-- "pagebrowser" -> Page Browser (thumbnail grid)
local PAGE_LONGPRESS_ACTION = "bookmap"
```

Change it to `"pagebrowser"` to open the thumbnail Page Browser instead of the
Book Map on a page‑number long‑press.

### Note on versioning

This patch replaces `SkimToWidget:init` and `:update` wholesale (the buttons it
changes are local variables buried inside `init`, so there's no cleaner seam).
That ties it to the KOReader version it was written against (**v2026.03**). If a
future KOReader update changes the Skim widget, refresh this patch from the new
`frontend/ui/widget/skimtowidget.lua`. If it ever fails to load, KOReader will
tell you at startup rather than failing silently.

---

## Credits & attribution

**`2-skim-location-history.lua`** — original work by
[**albertmichaelj**](https://github.com/albertmichaelj), created for this
repository (derived from KOReader's own `skimtowidget.lua`).

## License

**AGPL‑3.0** — full text in [`LICENSE`](LICENSE). The patch is derived from
KOReader's own source (`skimtowidget.lua`), which is also **AGPL‑3.0**.

Copyright © 2026 [albertmichaelj](https://github.com/albertmichaelj).

As a copyleft license, AGPL‑3.0 requires that redistributed and modified
versions remain under AGPL‑3.0. Please keep the attribution comment at the top
of the file intact.
