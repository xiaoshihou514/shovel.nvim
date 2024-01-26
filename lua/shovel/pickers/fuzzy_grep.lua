---@diagnostic disable: undefined-field
---@class FuzzyGrepResult
---@field score integer
---@field line string
---@field file string
---@field linenr integer
---@field pos integer[]

---@type string
local dir
local running = false
local YIELD_INTERVAL = 16
local RESULTS_CAP = 64
local counter = 0
---@type FuzzyGrepResult[]
local results = {}
local fzy = require("fzy")
local uv = vim.uv
local ignore = {
    ".git/",
}

local function is_ignored(s)
    for _, pattern in ipairs(ignore) do
        if s:match(pattern) then
            return true
        end
    end
    return false
end

local function grep(file, kw)
    local fd = assert(uv.fs_open(file, "r", 438))
    local stat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, stat.size, 0))
    assert(uv.fs_close(fd))
    -- HACK: fzy segfaults when given too long a line
    data = vim.tbl_map(function(l)
        return #l < 1024 and l or l:sub(1, 1024)
    end, vim.split(data, "\n", { plain = true }))
    local matches = fzy.filter(kw, data)

    for _, match in ipairs(matches) do
        local score = match[3]
        local ind = {
            score = score,
            line = data[match[1]],
            file = file,
            linenr = match[1],
            pos = match[2]
        }
        if #results < RESULTS_CAP then
            for i, res in ipairs(results) do
                if res.score > score then
                    table.insert(results, i, ind)
                    goto continue
                end
            end
            table.insert(results, ind)
            goto continue
        end
        -- have to be at least bigger than the lowest score
        if score <= results[1].score then
            goto continue
        end
        results[1] = nil
        local res
        for i = 2, RESULTS_CAP do
            res = results[i]
            if res.score > score then
                results[i - 1] = ind
                goto continue
            else
                results[i - 1] = res
            end
        end
        -- highest score
        results[RESULTS_CAP] = ind
        ::continue::
    end
end

---@param input FuzzyGrepResult
local function show(input)
    local iter = vim.iter(input):rev()
    local show_lines = {}
    local highlights = {}
    local base_dir = vim.fn.getcwd()
    for res in iter do
        local prefix = ("%s: %d  "):format(res.file:gsub(base_dir, ""), res.linenr)
        local show_line = prefix .. res.line
        table.insert(show_lines, show_line)
        for _, idx in ipairs(res.pos) do
            table.insert(highlights, {
                res.linenr - 1,    -- line
                #prefix + idx,     -- col_start
                #prefix + idx + 1, -- col_end
            })
        end
    end
    return show_lines, highlights
end

local function search(kw, args)
    if not running then
        dir = vim.fn.getcwd()
        running = true
        counter = 0
    else
        return false
    end
    for name, tp in vim.fs.dir(dir, { depth = math.huge }) do
        -- if counter >= YIELD_INTERVAL then
        -- counter = 0
        -- coroutine.yield(results)
        -- end
        if tp == "file" then
            local path = vim.fs.joinpath(dir, name)
            if not is_ignored(path) then
                grep(path, kw)
                counter = counter + 1
            end
        end
    end
    coroutine.yield(results)
    running = false
end

local function callback()
end

local co = coroutine.create(search)
local ok, partial = coroutine.resume(co, "vim", {})
assert(ok)
local lines, hl = show(partial)

return {
    show = show,
    search = search,
    callback = callback,
}
