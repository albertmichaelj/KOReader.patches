-- 2-fix-pagemap-order.lua
--
-- Work around a crengine bug: when an EPUB page-list is NOT in strict reading order,
-- LVDocView::updatePageMapInfo() clamps each entry's _page/_doc_y forward *in list
-- order* ("never go backward"). One out-of-order entry then reports every later entry
-- as being at the end of the book, so every page-map feature that maps a position to a
-- label (or a label to a page) returns the wrong value.
--
-- The clamp corrupts _page/_doc_y, but each entry's original `xpointer` survives into
-- Lua via getPageMap(), and getPageFromXPointer() resolves it to the TRUE rendered page
-- independently of the clamp (both it and getCurrentPage() return EXTERNAL page numbers,
-- so they're comparable). We rebuild a corrected, position-sorted map and answer from it.
--
-- Covered (all via CreDocument, all fail-safe):
--   getPageMap                  -> Go-to-page target, Page browser labels, TOC chapter
--                                  counts, "Stable page number list" menu
--   getPageMapCurrentPageLabel  -> footer current page
--   getPageMapXPointerPageLabel -> TOC entry page numbers, Bookmark page labels
-- NOT covered: getPageMapVisiblePageLabels (in-margin labels) -- would require
-- reimplementing crengine's on-screen geometry per page turn; left to the crengine fix.
-- getPageMapFirst/LastPageLabel are list-order labels (never clamped) -> already correct.
--
-- Side effect: getPageMap is returned sorted by true (reading-order) page, so the
-- "Stable page number list" menu shows in reading order rather than page-list order.
--
-- Stop-gap; the real fix belongs in crengine (fixing the data fixes ALL paths at once,
-- including the margin labels). Monkey-patches internals; re-verify after KOReader updates.

local CreDocument = require("document/credocument")

-- Corrected entries {page=true_page, label, xpointer, doc_y}, sorted ascending by page.
-- Cached on the document; rebuilt when the page count (pagination) changes.
local function buildSorted(self)
    local raw = self._document:getPageMap()
    if type(raw) ~= "table" or #raw == 0 then return nil end
    local list = {}
    for i = 1, #raw do
        local e = raw[i]
        local page = e.page
        if e.xpointer and e.xpointer ~= "" then
            local ok, p = pcall(self._document.getPageFromXPointer, self._document, e.xpointer)
            if ok and type(p) == "number" and p > 0 then page = p end
        end
        list[i] = { page = page, label = e.label, xpointer = e.xpointer, doc_y = e.doc_y }
    end
    table.sort(list, function(a, b) return a.page < b.page end)
    return list
end

local function sortedMap(self)
    local ok_pc, pages = pcall(self.getPageCount, self)
    pages = ok_pc and pages or 0
    if self.__pm ~= nil and self.__pm_pages == pages then
        return self.__pm or nil
    end
    local ok, m = pcall(buildSorted, self)
    self.__pm = (ok and m) or false
    self.__pm_pages = pages
    return self.__pm or nil
end

-- greatest index with map[i].page <= page
local function floorIdx(map, page)
    local idx = 1
    for i = 1, #map do
        if map[i].page <= page then idx = i else break end
    end
    return idx
end

-- (1) getPageMap: corrected + sorted; fresh tables so callers may add fields.
local orig_map = CreDocument.getPageMap
CreDocument.getPageMap = function(self)
    local m = sortedMap(self)
    if not m then return orig_map(self) end
    local out = {}
    for i = 1, #m do
        out[i] = { page = m[i].page, label = m[i].label, xpointer = m[i].xpointer, doc_y = m[i].doc_y }
    end
    return out
end

-- (2) current page label (footer)
local orig_current = CreDocument.getPageMapCurrentPageLabel
CreDocument.getPageMapCurrentPageLabel = function(self)
    local m = sortedMap(self)
    if m then
        local ok, cur = pcall(self._document.getCurrentPage, self._document)
        if ok and type(cur) == "number" then
            local idx = floorIdx(m, cur)
            return m[idx].label, idx, #m
        end
    end
    if orig_current then return orig_current(self) end
end

-- (3) label for any xpointer (TOC entry numbers, bookmarks)
local orig_xplabel = CreDocument.getPageMapXPointerPageLabel
CreDocument.getPageMapXPointerPageLabel = function(self, xp)
    local m = sortedMap(self)
    if m then
        local ok, p = pcall(self._document.getPageFromXPointer, self._document, xp)
        if ok and type(p) == "number" then
            local idx = floorIdx(m, p)
            return m[idx].label
        end
    end
    if orig_xplabel then return orig_xplabel(self, xp) end
end
