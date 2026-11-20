-- Overlays difftastic's token-level (AST) changes on Neovim's native diff mode.
-- Any tabpage with exactly two diff windows is treated as an old/new pair
-- (old on the left or top), which covers diffview, fugitive and gitsigns.

local api = vim.api
local M = {}

local ns = api.nvim_create_namespace('difft_overlay')
local muted_groups = { 'DiffAdd', 'DiffChange', 'DiffText' }
local enabled = false
local rendered = {} -- new buf -> key of the buffer states last sent to difft
local marked = {} -- bufs carrying our extmarks
local pending = false

local function blend(a, b, t)
  local function ch(shift)
    local x, y = bit.band(bit.rshift(a, shift), 0xff), bit.band(bit.rshift(b, shift), 0xff)
    return bit.lshift(math.floor(x + (y - x) * t + 0.5), shift)
  end
  return ch(16) + ch(8) + ch(0)
end

local function set_highlights()
  local function fg(name, fallback)
    return api.nvim_get_hl(0, { name = name, link = false }).fg or fallback
  end
  local normal = api.nvim_get_hl(0, { name = 'Normal', link = false })
  local hunk = normal.bg and normal.fg and { bg = blend(normal.bg, normal.fg, 0.07) } or { link = 'CursorLine' }
  hunk.default = true
  api.nvim_set_hl(0, 'DifftHunk', hunk)
  api.nvim_set_hl(0, 'DifftRemoved', { fg = fg('Removed', 0xf7768e), bold = true, default = true })
  api.nvim_set_hl(0, 'DifftAdded', { fg = fg('Added', 0x9ece6a), bold = true, default = true })
end

-- Replace the native line/word diff colours with a faint hunk background,
-- so only difftastic's tokens stand out.
local function mute(win)
  local cur = vim.wo[win].winhighlight
  if not cur:find('DifftHunk', 1, true) then
    vim.w[win].difft_winhl = cur
  end
  local map = {}
  for item in vim.gsplit(cur, ',', { trimempty = true }) do
    local from, to = item:match('^(.-):(.*)$')
    map[from] = to
  end
  for _, group in ipairs(muted_groups) do
    map[group] = 'DifftHunk'
  end
  local items = {}
  for from, to in pairs(map) do
    items[#items + 1] = from .. ':' .. to
  end
  vim.wo[win].winhighlight = table.concat(items, ',')
end

local function unmute(win)
  local saved = vim.w[win].difft_winhl
  if saved and vim.wo[win].winhighlight:find('DifftHunk', 1, true) then
    vim.wo[win].winhighlight = saved
  end
  vim.w[win].difft_winhl = nil
end

local function mark(buf, side, group)
  if not side then
    return
  end
  for _, change in ipairs(side.changes) do
    api.nvim_buf_set_extmark(buf, ns, side.line_number, change.start, {
      end_col = change['end'],
      hl_group = group,
      priority = 250,
      strict = false,
    })
  end
end

local function render(old_win, new_win)
  local old, new = api.nvim_win_get_buf(old_win), api.nvim_win_get_buf(new_win)
  local key = table.concat({ old, vim.b[old].changedtick, new, vim.b[new].changedtick }, ':')
  if rendered[new] == key then
    return
  end
  rendered[new] = key

  -- difftastic picks the language from the file name.
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(new), ':t')
  if name == '' then
    name = 'buffer'
  end
  local dir = vim.fn.tempname()
  local paths = {}
  for side, buf in pairs({ old = old, new = new }) do
    vim.fn.mkdir(dir .. '/' .. side, 'p')
    paths[side] = dir .. '/' .. side .. '/' .. name
    vim.fn.writefile(api.nvim_buf_get_lines(buf, 0, -1, false), paths[side])
  end

  vim.system(
    { 'difft', '--display', 'json', paths.old, paths.new },
    { env = { DFT_UNSTABLE = 'yes' }, text = true },
    vim.schedule_wrap(function(res)
      vim.fn.delete(dir, 'rf')
      if rendered[new] ~= key or not (api.nvim_buf_is_valid(old) and api.nvim_buf_is_valid(new)) then
        return
      end
      local ok, out = pcall(vim.json.decode, res.stdout)
      if res.code ~= 0 or not ok then
        vim.notify_once('difft_overlay: difft failed: ' .. (res.stderr or ''), vim.log.levels.WARN)
        return
      end
      api.nvim_buf_clear_namespace(old, ns, 0, -1)
      api.nvim_buf_clear_namespace(new, ns, 0, -1)
      marked[old], marked[new] = true, true
      for _, chunk in ipairs(out.chunks or {}) do
        for _, line in ipairs(chunk) do
          mark(old, line.lhs, 'DifftRemoved')
          mark(new, line.rhs, 'DifftAdded')
        end
      end
      for _, win in ipairs({ old_win, new_win }) do
        if api.nvim_win_is_valid(win) and vim.wo[win].diff then
          mute(win)
        end
      end
    end)
  )
end

local function diff_pairs()
  local result = {}
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    local wins = vim.tbl_filter(function(win)
      return vim.wo[win].diff
    end, api.nvim_tabpage_list_wins(tab))
    if #wins == 2 then
      table.sort(wins, function(a, b)
        local pa, pb = api.nvim_win_get_position(a), api.nvim_win_get_position(b)
        if pa[2] ~= pb[2] then
          return pa[2] < pb[2]
        end
        return pa[1] < pb[1]
      end)
      result[#result + 1] = wins
    end
  end
  return result
end

local function refresh()
  pending = false
  local live = {}
  local pairs_ = enabled and diff_pairs() or {}
  for _, wins in ipairs(pairs_) do
    live[api.nvim_win_get_buf(wins[1])] = true
    live[api.nvim_win_get_buf(wins[2])] = true
  end
  for buf in pairs(marked) do
    if not live[buf] then
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
      marked[buf], rendered[buf] = nil, nil
    end
  end
  for _, wins in ipairs(pairs_) do
    render(wins[1], wins[2])
  end
end

local function schedule_refresh()
  if not pending then
    pending = true
    vim.defer_fn(refresh, 30)
  end
end

function M.enable()
  enabled = true
  schedule_refresh()
end

function M.disable()
  enabled = false
  for _, win in ipairs(api.nvim_list_wins()) do
    unmute(win)
  end
  refresh()
end

function M.setup()
  set_highlights()
  local group = api.nvim_create_augroup('difft_overlay', {})
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_highlights })
  api.nvim_create_autocmd(
    { 'DiffUpdated', 'BufWinEnter', 'WinClosed', 'TextChanged', 'InsertLeave', 'BufWritePost' },
    { group = group, callback = schedule_refresh }
  )
  api.nvim_create_autocmd('OptionSet', { group = group, pattern = 'diff', callback = schedule_refresh })
  api.nvim_create_user_command('DifftOverlay', function()
    if enabled then
      M.disable()
    else
      M.enable()
    end
  end, { desc = 'Toggle difftastic overlay in diff windows' })
  M.enable()
end

return M
