local M = {}
local api, bind = vim.api, vim.keymap.set
local ns = api.nvim_create_namespace("Shovel")
local group = api.nvim_create_augroup("Shovel", {})
local function autocmd(ev, opts)
    opts.group = group
    api.nvim_create_autocmd(ev, opts)
end

---@class UIState
---@field input_buf integer
---@field input_win integer
---@field list_buf integer
---@field list_win integer

-- we only allow one picker at a time
local state = {
    ---@type UIState
    ui = {
        input_buf = -1,
        input_win = -1,
        list_buf = -1,
        list_win = -1,
    },
    ---@type thread
    search_co = nil,
    ---@type any[]
    results = {},
}
local is_running = false

---@param co thread
local function try_yield(co)
    if co then
        coroutine.yield(co)
    end
    return nil
end

function M.new(opts)
    if is_running then
        vim.notify("[shovel.nvim]: an instance is already running!", vim.log.levels.WARN)
        return
    end
    is_running = true

    -- validate arguments
    vim.validate({
        opts = { opts, "table" },
        ["opts.show"] = { opts.show, "function" },
        ["opts.search"] = { opts.search, "function" },
        ["opts.callback"] = { opts.callback, "function" }
    })
    opts.theme = opts.theme or require("shovel.theme").ivy

    local tbl = {}

    function tbl:show(args)
        state.ui = opts.theme()
        -- if window got closed we want to gracefully exit
        autocmd("WinClosed", {
            pattern = state.ui.input_win,
            callback = function()
                api.nvim_buf_delete(state.ui.input_buf, { force = true })
                api.nvim_buf_delete(state.ui.input_buf, { force = true })
                api.nvim_win_close(state.ui.list_win, true)
                state.ui = nil
                state.search_co = try_yield(state.search_co)
                opts.callback(nil)
            end
        })
        -- if search term changed we want to update
        autocmd("TextChanged", {
            buffer = state.ui.input_buf,
            callback = function()
                local keyword = api.nvim_buf_get_lines(state.ui.input_buf, 0, -1, false)[1]
                state.search_co = try_yield(state.search_co)
                state.search_co = coroutine.create(opts.search)
                local ok, results = coroutine.resume(state.search_co, keyword, args)
                assert(ok)
                state.results = results
                local show_items, highlights = opts.show(results, args)
                api.nvim_buf_set_lines(state.ui.list_buf, 0, -1, false, show_items)
                for _, hl in ipairs(highlights) do
                    api.nvim_buf_add_highlight(state.ui.list_buf, ns, unpack(hl))
                end
                coroutine.resume(state.search_co, keyword)
            end
        })
        -- closes picker
        bind("n", "<Esc>", function()
            api.nvim_win_close(0, true)
        end, { buffer = state.ui.input_buf })
        -- changing selected item
        local select_next = function()
            api.nvim_win_call(state.ui.list_win, function()
                local pos = api.nvim_win_get_cursor(state.ui.list_win)
                pos[1] = pos[1] + 1
                api.nvim_win_set_cursor(state.ui.list_win, pos)
            end)
        end
        local select_prev = function()
            api.nvim_win_call(state.ui.list_win, function()
                local pos = api.nvim_win_get_cursor(state.ui.list_win)
                pos[1] = pos[1] - 1
                api.nvim_win_set_cursor(state.ui.list_win, pos)
            end)
        end
        bind("i", "C-n", select_next, { buffer = state.ui.input_buf })
        bind("i", "C-p", select_prev, { buffer = state.ui.input_buf })
        bind("n", "j", select_next, { buffer = state.ui.input_buf })
        bind("n", "k", select_prev, { buffer = state.ui.input_buf })
        -- select item
        local select = function(msg)
            -- TODO
        end
        bind({ "n", "i" }, "<cr>", function()
            select("")
        end, opts)
        bind({ "n", "i" }, "<C-x>", function()
            select("vertical")
        end, opts)
        bind({ "n", "i" }, "<C-o>", function()
            select("horizontal")
        end, opts)
    end

    return tbl
end

api.nvim_create_user_command("Shovel", function(opts)
    local args = opts.fargs[1]
    local picker = table.remove(args, 1)
    M.new(require("shovel.pickers." .. picker)):show(args)
end, { nargs = "+" })

return M
