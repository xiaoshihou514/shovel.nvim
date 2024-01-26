local M = {}
local api = vim.api

_G._shovel_stc_input = function()
    if vim.v.lnum == api.nvim_win_get_cursor(0)[1] then
        return "%#ShovelPrompt#  %*"
    else
        return ""
    end
end

_G._shovel_stc_list = function()
    if vim.v.lnum == api.nvim_win_get_cursor(0)[1] then
        return "%#ShovelListPrompt#  %*"
    else
        return ""
    end
end

function M.ivy()
    local list_buf = api.nvim_create_buf(false, true)
    local input_buf = api.nvim_create_buf(false, true)
    local list_win_height = math.ceil(vim.o.lines * 0.8)
    local list_win = api.nvim_open_win(list_buf, true, {
        relative = "editor",
        width = vim.o.columns,
        height = list_win_height,
        row = vim.o.lines - list_win_height + 1,
        col = 0,
        focusable = false,
        style = "minimal",
    })
    local input_win = api.nvim_open_win(input_buf, true, {
        relative = "editor",
        width = vim.o.columns,
        height = 1,
        row = vim.o.lines - list_win_height - 1,
        col = 0,
        style = "minimal",
    })
    api.nvim_set_option_value("statuscolumn", "%!v:lua._shovel_stc()", { win = list_win })
    api.nvim_set_option_value("statuscolumn", "%!v:lua._shovel_stc()", { win = input_win })
    return {
        input_buf = input_buf,
        input_win = input_win,
        list_buf = list_buf,
        list_win = list_win
    }
end

M.default()

return M
