# KOReader User Patches

Two [KOReader](https://github.com/koreader/koreader) user patches: one that turns
the Skim dialog's bookmark buttons into **location‑history navigation**, and one
that **fixes wrong EPUB page numbers** caused by a crengine page‑map bug.

| Patch | What it does | Origin |
|---|---|---|
| [`2-skim-location-history.lua`](#2-skim-location-historylua--skim-location-history) | Location‑history navigation in the Skim dialog | **Original** |
| [`2-fix-pagemap-order.lua`](#2-fix-pagemap-orderlua--page-map-order-fix) | Corrects EPUB page numbers when the page‑list is out of reading order | **Original** (stop‑gap for [crengine#688](https://github.com/koreader/crengine/issues/688)) |

> Tested on KOReader **v2026.03** (Kindle). Both patches monkey‑patch KOReader
> internals, so re‑verify them after a KOReader update. They are independent —
> install either or both.

---

## What is a user patch?

A user patch is a `.lua` file that KOReader runs at startup to modify its own
behaviour, without you having to edit (or fork) KOReader itself. Patches live in
a `patches/` folder inside your KOReader directory and are applied
automatically.

The numeric prefix sets *when* a patch runs and the order patches run in
(natural sort, so `2-…` before `10-…`):

- `1-…` – early, before the UI is ready
- `2-…` – late, after the UI is ready (what these patches use)
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

## `2-fix-pagemap-order.lua` — Page-map order fix

**Original work.** A stop‑gap for a **crengine** bug that makes EPUB page
numbers wrong. Upstream issue (with full analysis and a proposed C++ fix):
[koreader/crengine#688 — *EPUB page numbers freeze when the page-list nav is not
in spine/reading order*](https://github.com/koreader/crengine/issues/688).

### The problem

An EPUB can carry a **page‑list** that maps print‑edition page numbers onto
positions in the book. The spec doesn't require that list to be in reading
order, and some perfectly conformant EPUBs aren't.

crengine's `LVDocView::updatePageMapInfo()` clamps each entry's position forward
**in list order** — a "never go backward" rule. So a single out‑of‑order entry
makes *every later entry* report as being at the end of the book. The visible
symptom is page numbers that freeze: you see `i, i, i, i, ii` where you should
see `i, 1, 2, 3, ii`. Everything that maps a position to a label (or a label back
to a page) then returns the wrong value.

### How the patch works

The clamp corrupts each entry's `_page`/`_doc_y`, but the entry's original
`xpointer` survives into Lua via `getPageMap()`. `getPageFromXPointer()` resolves
that xpointer to the **true** rendered page independently of the clamp (both it
and `getCurrentPage()` return external page numbers, so they're comparable). The
patch rebuilds a corrected, position‑sorted page map from the xpointers and
answers queries from it, overriding three `CreDocument` methods:

| Override | Fixes |
|---|---|
| `getPageMap` | Go‑to‑page target, Page Browser labels, TOC chapter counts, "Stable page number list" menu |
| `getPageMapCurrentPageLabel` | Footer current page |
| `getPageMapXPointerPageLabel` | TOC entry page numbers, bookmark page labels |

The corrected map is cached on the document and rebuilt only when the page count
(pagination) changes. Every override is **fail‑safe**: if anything goes wrong, or
the book has no page map at all, it falls back to the original method — so books
without a page‑list, and books whose page‑list is already in order, are
unaffected.

### Limitations

- **Not covered:** `getPageMapVisiblePageLabels` — the labels drawn in the page
  margin. Fixing those in Lua would mean reimplementing crengine's on‑screen
  geometry on every page turn; that's left to the upstream fix.
- **Already correct:** `getPageMapFirst/LastPageLabel` are list‑order labels and
  are never clamped.
- **Side effect:** since `getPageMap` now returns entries sorted by true reading
  order, the "Stable page number list" menu lists them in reading order rather
  than raw page‑list order.

This is a stop‑gap. The real fix belongs in crengine — correcting the data there
fixes every code path at once, including the margin labels. Because the patch
monkey‑patches internals, re‑verify it after KOReader updates.

---

## Credits & attribution

Both patches are original work by
[**albertmichaelj**](https://github.com/albertmichaelj), created for this
repository:

- **`2-skim-location-history.lua`** — derived from KOReader's own
  `skimtowidget.lua`.
- **`2-fix-pagemap-order.lua`** — works around a crengine bug; see
  [crengine#688](https://github.com/koreader/crengine/issues/688).

## License

**AGPL‑3.0** — full text in [`LICENSE`](LICENSE). These patches extend KOReader,
which is itself **AGPL‑3.0** (the skim patch in particular incorporates code from
KOReader's `skimtowidget.lua`).

Copyright © 2026 [albertmichaelj](https://github.com/albertmichaelj).

As a copyleft license, AGPL‑3.0 requires that redistributed and modified
versions remain under AGPL‑3.0. Please keep the attribution comments at the top
of each file intact.
