-- 2-chapter-pages-left-screens.lua
--
-- Footer: make "pages left in chapter" (the "=>" / "⇒" item) count SCREEN pages -- how
-- many screen page-turns until the chapter ends -- instead of publisher/reference page
-- numbers, even when static (publisher) page numbers are enabled.
--
-- Why this works: ReaderToc:getChapterPagesLeft(pageno, screen_pages) already returns
-- rendered/screen pages when screen_pages is true; callers that want reference pages
-- simply omit the argument, which on a page-mapped book takes the reference-page branch.
-- Forcing true therefore affects exactly the callers that omit it -- and all of those are
-- "pages left in chapter" displays:
--   * readerfooter.lua      -- the footer's "pages_left" ("=>" / "⇒") item
--   * filemanagerbookinfo.lua -- the "%l" pattern, used by the sleep-screen message
--                                and the footer's custom-text item
-- Callers that already pass true (the "chapter time to read" item, and the "%h" pattern)
-- are untouched, so time-to-read estimates keep using screen pages as they already did.
--
-- Note: this affects "pages left in chapter" only. If you also show "chapter progress"
-- (current/total pages within the chapter), that still uses reference pages -- ask and
-- it can be converted the same way (getChapterPageCount / getChapterPagesDone).

local ReaderToc = require("apps/reader/modules/readertoc")
local orig_getChapterPagesLeft = ReaderToc.getChapterPagesLeft
ReaderToc.getChapterPagesLeft = function(self, pageno, screen_pages) -- luacheck: ignore screen_pages
    return orig_getChapterPagesLeft(self, pageno, true)
end
