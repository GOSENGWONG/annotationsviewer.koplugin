-- anv_data.lua — Annotations Viewer
--
-- Sidecar data layer: reads and caches KOReader highlight and bookmark
-- sidecars, matches notes to stored entries and edits annotations. An
-- in-memory cache is backed by a persistent on-disk cache; main.lua calls
-- bind(deps) after load to inject collaborators that were nil at load time.
--
-- Public API (used by other modules):
--   getSidecarKey    cache key for a book's highlight sidecar
--   getBookInfoKey    cache key for a book's metadata
--   normalizeColorStyle    canonical style name for a highlight
--   colorStyleMatches    whether a note matches a color style
--   itemMatchesNote    whether a sidecar entry matches a note
--   nowStamp    current timestamp string
--   getLiveReader    live ReaderUI for an open book, if any
--   findLiveIndex    index of a note in the live highlight list
--   editStoredAnnotation    apply an edit to a stored sidecar entry
--   setLiveHighlightField    update a field in the live highlight list
--   clearCaches / invalidateBook    drop cached sidecar/book data
--   loadPersistentCache / savePersistentCache    load or write on-disk cache
--   markPersistDirty / isPersistLoaded    track pending cache writes
--   bind    inject NotesListWidget collaborator
--   _annotation_cache / _book_info_cache    caches main.lua reads and writes directly

local Data = {}

local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local DocSettings = require("docsettings")
local lfs = require("libs/libkoreader-lfs")
local core = require("anv_core")

local NotesListWidget -- injected by main assembly

function Data.normalizeColorStyle(af)
    if type(af) ~= "table" then return end
    local function valid(t, v) return (t == "color" or t == "style") and type(v) == "string" and v ~= "" end
    local inc = valid(af.type, af.value)
    local exc = valid(af.type_exclude, af.value_exclude)
    if inc then
        af.cs = type(af.cs) == "table" and af.cs or {}
        af.cs[af.type .. ":" .. af.value] = true
        af.cs_exclude = false
        -- an old filter that also hid something: "show yellow, hide Underline" is "yellow, with
        -- any style but Underline" (colours and styles together must both match). Hiding the same
        -- kind as the one shown adds nothing.
        if exc and af.type_exclude ~= af.type then
            if af.type_exclude == "style" then
                local styles = { "lighten", "underscore", "strikeout", "invert" }
                for n = 1, #styles do
                    if styles[n] ~= af.value_exclude then af.cs["style:" .. styles[n]] = true end
                end
            else
                local colors = ReaderHighlight.highlight_colors or {}
                for n = 1, #colors do
                    local key = colors[n][2]
                    if type(key) == "string" and key ~= af.value_exclude then af.cs["color:" .. key] = true end
                end
            end
        end
    elseif exc and not (type(af.cs) == "table" and next(af.cs)) then
        af.cs = { [af.type_exclude .. ":" .. af.value_exclude] = true }
        af.cs_exclude = true
    end
    af.type, af.value, af.type_exclude, af.value_exclude = nil, nil, nil, nil
    -- drop what can't be a colour or style (a hand-edited or broken saved filter)
    if af.cs ~= nil and type(af.cs) ~= "table" then af.cs = nil end
    if af.cs then
        for k in pairs(af.cs) do
            local t, v
            if type(k) == "string" then t, v = k:match("^(%a+):(.+)$") end
            if not valid(t, v) or af.cs[k] ~= true then af.cs[k] = nil end
        end
    end
    if af.cs and not next(af.cs) then af.cs, af.cs_exclude = nil, nil end
end
function Data.colorStyleMatches(af, note)
    local nw = core.NoteWrapper:new(note)
    local c, d = nw:getNormalizedColor(), nw:getNormalizedDrawer()
    local has_c, has_s, hit_c, hit_s = false, false, false, false
    for k in pairs(af.cs) do
        local t, v = k:match("^(%a+):(.+)$")
        if t == "color" then has_c = true; if v == c then hit_c = true end
        elseif t == "style" then has_s = true; if v == d then hit_s = true end end
    end
    if af.cs_exclude then return not (hit_c or hit_s) end
    -- several colours: any of them; colours and styles together: both must match. A highlight
    -- without a colour (Invert never has one, nor do some older highlights) matches on its style
    -- alone, or Invert with a colour would never show anything.
    if has_c and has_s and hit_s and (c == nil or d == "invert") then return true end
    return (not has_c or hit_c) and (not has_s or hit_s)
end

Data._annotation_cache = {}  -- [book_path] = { data = {...}, mtime = key }
Data._book_info_cache   = {}  -- [book_path] = { data = {...}, mtime = key }

function Data.fileStamp(path)
    local attr = path and lfs.attributes(path)
    if attr and attr.mode == "file" then
        return attr.modification .. ":" .. attr.size
    end
end

-- Returns a key for the current state of a book's sidecar, plus the sidecar path.
-- The second value is false when the book definitely has no sidecar (so no annotations),
-- and nil when that can't be determined (KOReader < 2023).
-- The sidecar is the one KOReader's DocSettings:open would read, found without its side effects
-- (open() deletes empty or broken files): every place KOReader keeps one (book folder, docsettings
-- folder, hash folder when in use, history folder, and their ".old" backups), the most recently
-- changed first; a backup never goes before its own file.
function Data.getSidecarKey(book_path)
    local ok, list = pcall(function()
        return NotesListWidget.sidecarCandidates(book_path)
    end)
    if ok and type(list) == "table" then
        -- readSidecar() may fall back to a ".old" backup or another location, so key on every
        -- readable candidate: a change to any of them must invalidate the cache.
        local parts, sidecar = nil, nil
        for i = 1, #list do
            local c = list[i]
            if c.size > 0 then
                parts = parts or {}
                parts[#parts + 1] = c.path .. ":" .. (c.mtime or "") .. ":" .. c.size
                if not sidecar then sidecar = c.path end
            end
        end
        if sidecar then return table.concat(parts, "|"), sidecar end
    end
    -- Fall back to the book file itself. false: KOReader looked and there is no sidecar;
    -- nil: it couldn't look (`a and false or nil` would always give nil)
    local none = nil
    if ok then none = false end
    return "book:" .. (Data.fileStamp(book_path) or ""), none
end

-- Key for the book info (title/authors/tags): the sidecar key plus the custom metadata file
-- actually read. custom_metadata_file is the path returned by DocSettings:findCustomMetadataFile,
-- which may live in a different folder from the sidecar; the sidecar directory is only a fallback
-- for older KOReader that has no such API.
function Data.getBookInfoKey(sidecar_key, sidecar, custom_metadata_file)
    local stamp
    if type(custom_metadata_file) == "string" then
        stamp = Data.fileStamp(custom_metadata_file) or ""
    else
        local dir = sidecar and sidecar:match("^(.*)/")
        stamp = (dir and Data.fileStamp(dir .. "/custom_metadata.lua")) or ""
    end
    return sidecar_key .. "|" .. stamp
end

-- On-disk copy of the caches above, so a KOReader restart doesn't mean parsing every
-- book's sidecar again. Bump CACHE_VERSION whenever the cached data's shape changes.
Data.CACHE_VERSION = 5 -- 3: bookmarks and page labels are kept; 4: old-format books marked legacy, with notes;
                        -- 5: book info keeps series and language
Data._persist = nil        -- LuaSettings object, loaded on the first scan
Data._persist_dirty = false
Data._persist_paths = nil -- signature of the path set last written to disk

local function pathSignature(paths)
    local sorted = {}
    for i = 1, #paths do sorted[i] = paths[i] end
    table.sort(sorted)
    return table.concat(sorted, "\0")
end

function Data.loadPersistentCache()
    if Data._persist then return end
    local ok_ds, DataStorage = pcall(require, "datastorage")
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    if not (ok_ds and ok_ls) then return end
    local dir = DataStorage:getDataDir() .. "/cache"
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local ok, settings = pcall(LuaSettings.open, LuaSettings, dir .. "/annotationsviewer.lua")
    if not ok or not settings then return end
    Data._persist = settings
    local d = settings.data
    if d.version ~= Data.CACHE_VERSION or type(d.books) ~= "table" then
        settings.data = { version = Data.CACHE_VERSION, books = {} }
        Data._persist_dirty = true
        return
    end
    for path, b in pairs(d.books) do
        if not Data._annotation_cache[path] and b.key and b.annotations then
            Data._annotation_cache[path] = { data = b.annotations, mtime = b.key }
        end
        if not Data._book_info_cache[path] and b.info_key and b.info then
            Data._book_info_cache[path] = { data = b.info, mtime = b.info_key }
        end
    end
    -- _persist_paths stays nil: the saved "books" only holds annotated books, not the full
    -- scanned set, so the first scan of a session writes once and then records the real set.
end

-- Writes the caches for the given books (the ones found by the last scan) back to disk,
-- but only if something was read from a sidecar since the last save.
function Data.savePersistentCache(paths)
    if not Data._persist then return end
    local sig = pathSignature(paths)
    -- A same-sized but different set of paths must still be saved, so compare the set, not its size.
    if not Data._persist_dirty and sig == Data._persist_paths then return end
    local books = {}
    for _, path in ipairs(paths) do
        local a, i = Data._annotation_cache[path], Data._book_info_cache[path]
        if a then
            books[path] = {
                key = a.mtime, annotations = a.data,
                info_key = i and i.mtime, info = i and i.data,
            }
        end
    end
    Data._persist.data = { version = Data.CACHE_VERSION, books = books }
    -- LuaSettings:flush returns self even when the underlying write silently fails, so only a
    -- raised error is detectable here. On failure keep the state so the next scan retries.
    local ok, err = pcall(Data._persist.flush, Data._persist)
    if not ok then
        logger.warn("AnnotationsViewer: could not save cache:", err)
        return
    end
    Data._persist_dirty = false
    Data._persist_paths = sig
end

-- Write-back helpers -------------------------------------------------------------------

function Data.positionsEqual(a, b)
    if a == b then return true end
    if type(a) == "table" and type(b) == "table" then -- PDF/CBZ positions
        return a.x == b.x and a.y == b.y and a.page == b.page
    end
    return false
end

-- Does a stored or live annotation item correspond to this plugin note?
-- Matches on date, highlighted text and position, so two highlights saved in the same
-- second with the same text are told apart.
function Data.itemMatchesNote(item, note)
    -- the list keeps "" for an item without a date, so compare both the same way
    if (item.datetime or "") ~= (note.datetime or "") then return false end
    if note.bookmark then -- a bookmark has no text of its own: match on its place
        return item.drawer == nil and Data.positionsEqual(item.page or item.pageno, note.page)
    end
    if (item.text or "") ~= (note.highlighted_text or "") then return false end
    if note.pos0 ~= nil then
        return Data.positionsEqual(item.pos0, note.pos0) and Data.positionsEqual(item.pos1, note.pos1)
    end
    -- no xpointer (old EPUB sidecars, or hand-edited data): fall back to the page so two
    -- same-second, same-text highlights on different pages aren't mistaken for each other
    return Data.positionsEqual(item.page or item.pageno, note.page)
end

-- Returns the ReaderUI if this book is currently open, so changes go through KOReader.
function Data.getLiveReader(book_path)
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI and ReaderUI.instance
    if ui and ui.document and NotesListWidget.samePath(ui.document.file, book_path)
            and ui.annotation and ui.annotation.annotations then
        return ui
    end
end

function Data.findLiveIndex(ui, note)
    for i, item in ipairs(ui.annotation.annotations) do
        if Data.itemMatchesNote(item, note) then return i end
    end
end

-- Finds the annotation for `note` in its (closed) book's sidecar, calls fn(item, list, index)
-- on it and saves the sidecar. Returns true if the annotation was found.
function Data.editStoredAnnotation(note, fn)
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, note.book_path)
    if not ok or not doc_settings or not doc_settings.data then return false end
    local data = doc_settings.data
    local found = false
    if type(data.annotations) == "table" then
        for i, item in ipairs(data.annotations) do
            if Data.itemMatchesNote(item, note) then
                fn(item, data.annotations, i)
                found = true
                break
            end
        end
    end
    -- an old-format sidecar (no `annotations` list) is never written: see AllNotesViewer.legacyBlocked
    if not found then return false end
    -- DocSettings:flush returns the sidecar dir on success, nil if every write failed, and may
    -- raise. Only report success once the data actually reached disk.
    local ok, saved = pcall(doc_settings.flush, doc_settings)
    return ok and saved ~= nil
end

function Data.nowStamp() return os.date("%Y-%m-%d %H:%M:%S") end

-- Changes the style or colour of a highlight in the open book, the way ReaderHighlight does
-- (including the PDF annotation), and tells KOReader about the real item.
function Data.setLiveHighlightField(ui, index, field, value)
    local item = ui.annotation.annotations[index]
    local hl = ui.highlight
    local pdf = hl and hl.writePdfAnnotation
    if pdf then hl:writePdfAnnotation("delete", item) end
    item[field] = value
    if pdf and ui.paging then
        hl:writePdfAnnotation("save", item)
        if item.note then hl:writePdfAnnotation("content", item, item.note) end
    end
    ui:handleEvent(Event:new("AnnotationsModified", { item }))
    UIManager:setDirty(ui.dialog) -- repainted with the new colour / style when the list closes
end

-- Cache state is module-local (loadPersistentCache replaces _persist at runtime), so callers
-- reach the scalars through these accessors rather than capturing a stale snapshot.
function Data.clearCaches()
    for k in pairs(Data._annotation_cache) do Data._annotation_cache[k] = nil end
    for k in pairs(Data._book_info_cache) do Data._book_info_cache[k] = nil end
    if Data._persist then
        Data._persist.data = { version = Data.CACHE_VERSION, books = {} }
        pcall(Data._persist.flush, Data._persist)
    end
    Data._persist, Data._persist_dirty, Data._persist_paths = nil, false, nil
end
function Data.invalidateBook(book_path)
    Data._annotation_cache[book_path] = nil
    -- book_info rarely changes, but clear it too so tags/title edits are reflected
    Data._book_info_cache[book_path] = nil
end
function Data.markPersistDirty() Data._persist_dirty = true end
function Data.isPersistLoaded() return Data._persist ~= nil end

function Data.bind(deps)
    if deps.NotesListWidget then NotesListWidget = deps.NotesListWidget end
end

return Data
