local lib = {}

lib.bind = function(desc, mode, keys, action, opts)
  opts = opts or {}
  opts.desc = desc
  opts.silent = opts.silent ~= false
  vim.keymap.set(mode, keys, action, opts)
end

-------- Projects --------------------------------------------------------------------------------------------

-- Find the nearest project root from the current buffer or cwd
lib.project_root = function()
  -- 0) Resolve buffer or cwd
  local bufname = vim.api.nvim_buf_get_name(0)
  local dir = nil

  if bufname ~= "" then
    local stat = vim.uv.fs_stat(bufname)
    if stat and stat.type == "directory" then
      dir = bufname
    else
      dir = vim.fs.dirname(bufname)
    end
  end
  dir = dir or vim.uv.cwd()

  -- 1) Prefer any attached LSP root that contains the buffer
  local roots = {}
  for _, client in pairs(vim.lsp.get_clients { bufnr = 0 }) do
    local ws = client.config.workspace_folders
    local dir = nil
    if ws and ws[1] and ws[1].uri then
      dir = vim.uri_to_fname(ws[1].uri)
    end
    dir = dir or (type(client.config.root_dir) == 'function'
      and client.config.root_dir(bufname) or client.config.root_dir)
    if dir and bufname:find(dir, 1, true) then
      table.insert(roots, dir)
    end
  end
  table.sort(roots, function(a, b) return #a > #b end)
  local root = roots[1]

  -- 2) Else use nearest .gitlib
  if not root then
    local git = vim.fs.find('.git', { path = dir, upward = true })[1]
    if git then root = vim.fs.dirname(git) end
  end

  -- 3) Else use other project markers
  if not root then
    local markers = { 'package.json', 'pyproject.toml', 'Cargo.toml', 'go.mod', 'Gemfile' }
    local m = vim.fs.find(markers, { path = dir, upward = true })[1]
    if m then root = vim.fs.dirname(m) end
  end

  -- 4) Fallback: CWD
  return root or vim.uv.cwd()
end

-------- Buffers ---------------------------------------------------------------------------------------------

-- Append to a buffer
lib.append_buf = function(buf, line)
  -- Append, replacing the default empty line
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { line })
  else
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
  end

  -- Scroll if visible in a window
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
  end
end

-- Create a popup buffer closed with q
lib.popup_buf = function(width, height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
  })
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
  return buf
end

return lib
