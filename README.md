# KOReader User Patches

A small collection of [KOReader](https://github.com/koreader/koreader) user
patches. One is original work; the two header patches are sourced from
[joshuacant/KOReader.patches](https://github.com/joshuacant/KOReader.patches)
with a single original bug‑fix added on top (see
[The page‑browser fix](#the-pagebrowser-fix)).

| Patch | Origin |
|---|---|
| [`2-skim-location-history.lua`](#2-skim-location-historylua--skim-location-history) | **Original** |
| [`2-reader-header-centered.lua`](#header-patches-centered--cornered) | Sourced from [joshuacant/KOReader.patches](https://github.com/joshuacant/KOReader.patches) (+ original page‑browser fix) |
| [`2-reader-header-cornered.lua`](#header-patches-centered--cornered) | Sourced from [joshuacant/KOReader.patches](https://github.com/joshuacant/KOReader.patches) (+ original page‑browser fix) |

> Tested on KOReader **v2026.03** (Kindle). They should work on nearby
> versions, but see the per‑patch notes — the skim patch in particular is tied
> to the version it was written against.

---

## What is a user patch?

A user patch is a `.lua` file that KOReader runs at startup to modify its own
behaviour, without you having to edit (or fork) KOReader itself. Patches live in
a `patches/` folder inside your KOReader directory and are applied
automatically.

The numeric prefix sets *when* a patch runs and the order patches run in
(natural sort, so `2-…` before `10-…`):

- `1-…` – early, before the UI is ready
- `2-…` – late, after the UI is ready (what all of these use)
- `8-…` / `9-…` – just before / at exit

If a patch fails to load, KOReader shows an error popup at startup and you can
disable individual patches from **Menu → Tools (gear) → Patches**, so a broken
patch can never lock you out.

## Installation

1. Find your KOReader directory. On Kindle it is typically
   `/mnt/us/koreader/`; on other platforms it's wherever KOReader is installed
   (e.g. `~/.config/koreader/` on desktop Linux).
2. Create a `patches/` subfolder inside it if it doesn't already exist.
3. Copy the `.lua` file(s) you want into `koreader/patches/`.
4. Restart KOReader.

You can install any subset — the patches are independent of one another.

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

## Header patches (centered & cornered)

**Sourced from [joshuacant/KOReader.patches](https://github.com/joshuacant/KOReader.patches).**
These add a "header" to the top of the reading screen, mirroring the footer/status
bar at the bottom. They draw **only for reflowable documents** (EPUB and similar)
and never for fixed‑layout documents (PDF, CBZ).

- **`2-reader-header-centered.lua`** — a single, centred header line at the top
  of the screen. Ships configured to show the clock.
- **`2-reader-header-cornered.lua`** — two items, one in the top‑left and one in
  the top‑right corner (like the footer). Ships configured to show the book
  title (left) and author (right).

Both are configured *in code*: open the file and edit the clearly‑marked
sections (formatting options near the top, and the block that decides what text
is displayed). The available values — title, author, page progress, chapter
info, percentage, clock, battery, etc. — are set up as local variables with
comments; anything `ReaderFooter` can show, these can show too. See the comments
at the top of each file for details.

> **Tip:** the header draws *over* the page, so give your book enough top margin
> that the text isn't obscured.

### The page‑browser fix

> **This is the only part of the two header patches that is original to this
> repository.**

The upstream header patches hook `ReaderView:paintTo`, the method KOReader calls
to draw a page. The problem: KOReader also renders **Page Browser** and **Book
Map** thumbnails by calling that same method — but off‑screen, inside a
short‑lived subprocess. With the unmodified patches, the header‑drawing code
runs during thumbnail generation too; for EPUBs it tries to draw the header into
the off‑screen buffer, the subprocess produces no usable tile, and **thumbnails
spin forever and never load**.

The fix is a single guard added right after the existing `render_mode` check, so
the header is drawn only when painting to the real screen framebuffer and is a
no‑op during off‑screen thumbnail rendering:

```lua
if bb ~= Screen.bb then return end -- Only draw on the real screen; skip off-screen renders (page browser / book map thumbnails)
```

During normal reading, KOReader always paints widgets to `Screen.bb`; the
thumbnail path paints to a freshly‑allocated buffer instead, so the two are
cleanly distinguished. The header still appears while reading (and in
screenshots, which snapshot the screen directly), and thumbnails render cleanly
without the header baked into them.

If you write your own `ReaderView:paintTo` overlay patch, include the same guard
to avoid breaking thumbnailing.

---

## Credits & attribution

- **`2-skim-location-history.lua`** — original work by
  [**albertmichaelj**](https://github.com/albertmichaelj), created for this
  repository (derived from KOReader's own `skimtowidget.lua`).
- **`2-reader-header-centered.lua`** and **`2-reader-header-cornered.lua`** —
  authored by **joshuacant** and taken from
  [joshuacant/KOReader.patches](https://github.com/joshuacant/KOReader.patches).
  The only original modification made here, by
  [**albertmichaelj**](https://github.com/albertmichaelj), is the
  [page‑browser fix](#the-pagebrowser-fix) described above. All other credit for
  these two patches belongs to joshuacant.

If you find these useful, please also check out the upstream repo — it contains
many more patches than the two reproduced here.

## License

**AGPL‑3.0** — full text in [`LICENSE`](LICENSE). This matches both upstream
sources:

- The header patches are distributed by joshuacant under **AGPL‑3.0**.
- The skim patch is derived from KOReader's own source
  (`skimtowidget.lua`), which is also **AGPL‑3.0**.

Copyright © 2026 [albertmichaelj](https://github.com/albertmichaelj) for the
original contributions in this repository (the skim patch and the page‑browser
fix). The header patches remain copyright their original author, joshuacant.

As a copyleft license, AGPL‑3.0 requires that redistributed and modified
versions remain under AGPL‑3.0. Please keep the attribution comments at the top
of each file intact.
