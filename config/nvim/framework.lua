local F = {}

-------- Utils -----------------------------------------------------------------------------------------------

-- Makes a function `foo` lazy-capable with `foo.with(...args)` to turn it into a closure
local function lazy(fn)
  return setmetatable({
    with = function(...)
      local args = {...}
      return function()
        return fn(unpack(args))
      end
    end,
  }, {
    __call = function(_, ...)
      return fn(...)
    end,
  })
end

-- If `x` is callable, call it, otherwise return `x` as a value
local function call(x)
  if type(x) == 'function' then
    return x()
  end
  if type(x) == 'table' then
    local mt = getmetatable(x)
    if mt and mt.__call ~= nil then
      return x()
    end
  end
  return x
end

-------- Helpers ---------------------------------------------------------------------------------------------

-- Get current working directory
-- Uses buffer's directory if editing a file, otherwise vim's cwd
F.cwd = lazy(function()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname ~= "" then
    return vim.fn.fnamemodify(bufname, ':p:h')
  else
    return vim.fn.getcwd()
  end
end)

-- PROJECT -------------------------------------------------------------------------------------------------------

F.project = {
  -- Return all `.nvim` project directories from the top down
  all = function(path)
    path = path or vim.fn.expand('%:p:h')
    local dirs, seen = {}, {}
    for _, marker in ipairs({'.nvim', '.git'}) do
      for _, dir in ipairs(vim.fs.find(marker, { path = path, upward = true, type = 'directory' })) do
        local parent = vim.fs.dirname(dir)
        if not seen[parent] then
          seen[parent] = true
          table.insert(dirs, 1, parent) -- insert at start so topmost first
        end
      end
    end
    return dirs
  end,

  -- Find top-level project dir
  root = lazy(function(path)
    local dirs = F.project.all(path)
    return dirs[1]
  end),

  -- Find nearest (deepest) project dir
  nearest = lazy(function(path)
    local dirs = F.project.all(path)
    return dirs[#dirs]
  end),

  -- Create .nvim/ marker in current directory
  mark = function()
    return function()
      vim.fn.mkdir('.nvim', 'p')
      vim.notify('Created .nvim/ project marker')
    end
  end,

  -- Load project-specific config from .nvim/init.lua
  load = function()
    local dir = F.project.dir()
    if not dir then return end

    local init_file = dir .. '/.nvim/init.lua'
    if vim.fn.filereadable(init_file) == 1 then
      local chunk = loadfile(init_file)
      if chunk then
        local ok, result = pcall(chunk)
        return ok and result or {}
      end
    end
    return {}
  end,
}

-- PICK ------------------------------------------------------------------------------------------------------

F.pick = {
  -- File picker
  --   * dir: directory to search (default cwd)
  --   * depth: max search depth
  --   * hidden: include hidden files
  --   * gitignored: include gitignored files
  file = lazy(function(opts)
    opts = opts or {}
    local telescope_opts = {}

    -- Search in either opts.dir or the cwd
    local dir = call(opts.dir) or F.cwd()
    telescope_opts.cwd = vim.fn.expand(dir)
    telescope_opts.prompt_title = string.format('Files (%s)', dir)

    -- Build fd command based on options (depth/hidden/no_ignore)
    local cmd = { 'fd', '--type', 'f' }
    if opts.depth then
      table.insert(cmd, '--max-depth')
      table.insert(cmd, tostring(opts.depth))
    end
    if opts.hidden then table.insert(cmd, '--hidden') end
    if opts.gitignored then table.insert(cmd, '--no-ignore') end
    telescope_opts.find_command = cmd

    require('telescope.builtin').find_files(telescope_opts)
  end),

  -- Directory picker
  --   * dir: directory to search (default cwd)
  --   * depth: max search depth
  --   * hidden: include hidden directories
  --   * gitignored: include gitignored directories
  dir = lazy(function(opts)
    local tb = require('telescope.builtin')
    local actions = require('telescope.actions')
    local state = require('telescope.actions.state')

    opts = opts or {}
    local telescope_opts = {}

    -- Search in either opts.dir or the cwd
    local dir = opts.dir or F.cwd()
    telescope_opts.cwd = vim.fn.expand(dir)
    telescope_opts.prompt_title = string.format('Dirs (%s)', dir)

    -- Build fd command based on options (depth/hidden/no_ignore)
    local cmd = { 'fd', '--type', 'd' }
    if opts.depth then
      table.insert(cmd, '--max-depth')
      table.insert(cmd, tostring(opts.depth))
    end
    if opts.hidden then table.insert(cmd, '--hidden') end
    if opts.gitignored then table.insert(cmd, '--no-ignore') end
    telescope_opts.find_command = cmd

    -- Bind enter to cd and edit the selected dir
    telescope_opts.attach_mappings = function(_, map)
      map('i', '<cr>', function(prompt_bufnr)
        local entry = state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.cmd('cd ' .. entry.path)
        vim.cmd('edit .')
      end)
      return true
    end

    tb.find_files(telescope_opts)
  end),

  -- Buffer picker
  buffer = function()
    require('telescope.builtin').buffers()
  end,
}

-- GREP ------------------------------------------------------------------------------------------------------

-- Grep files or current buffer
-- opts:
--   * dir: directory to search (omit to grep current buffer)
--   * hidden: search hidden files
--   * gitignored: search gitignored files
F.grep = lazy(function(opts)
  opts = opts or {}

  -- Search in either opts.dir or the current buffer
  local dir = call(opts.dir)
  if not dir then
    require('telescope.builtin').current_buffer_fuzzy_find { prompt_title = 'Ripgrep (buffer)' }
  else
    local telescope_opts = {
      cwd = vim.fn.expand(dir),
      prompt_title = string.format('Ripgrep (%s)', dir)
    }

    -- Build rg args based on options
    if opts.hidden or opts.gitignore then
      telescope_opts.additional_args = function()
        local args = {}
        if opts.hidden then table.insert(args, '--hidden') end
        if opts.gitignore then table.insert(args, '--no-ignore') end
        return args
      end
    end

    require('telescope.builtin').live_grep(telescope_opts)
  end
end)

-- ACTIONS -------------------------------------------------------------------------------------------------------

-- Run shell command
F.shell = lazy(function(cmd)
  vim.cmd('!' .. cmd)
end)

-- Edit file
F.edit = lazy(function(path)
  path = vim.fn.expand(call(path))
  if path and path ~= "" then
    vim.cmd.edit(path)
  end
end)

-- Change directory
F.cd = lazy(function(path)
  path = vim.fn.expand(call(path))
  if path and path ~= "" then
    vim.cmd.cd(path)
  end
end)

-- Run vim command (caller should include : if needed, e.g. ':Yazi')
F.cmd = lazy(function(cmd)
  vim.cmd(cmd)
end)

-- LSP -----------------------------------------------------------------------------------------------------------

F.lsp = {
  -- Rename symbol
  rename = function()
    require('live-rename').map { insert = true }
  end,

  -- Go to definition
  definition = function()
    require('telescope.builtin').lsp_definitions()
  end,

  -- Find references
  references = function()
    require('telescope.builtin').lsp_references()
  end,

  -- Workspace symbols
  symbols = function()
    require('telescope.builtin').lsp_dynamic_workspace_symbols()
  end,

  -- Document symbols
  doc_symbols = function()
    require('telescope.builtin').lsp_document_symbols()
  end,

  -- Implementations
  implementations = function()
    require('telescope.builtin').lsp_implementations()
  end,

  -- Type definitions
  types = function()
    require('telescope.builtin').lsp_type_definitions()
  end,

  -- Code action
  action = function()
    vim.lsp.buf.code_action()
  end,

  -- Format buffer
  format = function()
    require('conform').format { async = true, lsp_format = 'fallback' }
  end,

  -- Jump to next diagnostic for a list of severities (e.g., {'ERROR','WARN'})
  next_diagnostic = lazy(function(severities)
    local function diagnostics(buf, sev)
      local ds
      if sev then
        ds = vim.diagnostic.get(buf, { severity = vim.diagnostic.severity[sev] })
      else
        ds = vim.diagnostic.get(buf)
      end
      table.sort(ds, function(a, b)
        if a.lnum == b.lnum then return a.col < b.col end
        return a.lnum < b.lnum
      end)
      return ds
    end

    local function next_in_buffer(sev, buf, line, col)
      local ds = diagnostics(buf, sev)
      if line ~= nil then
        for _, d in ipairs(ds) do
          if d.lnum + 1 > line or d.col > col then return d end
        end
      end
      return ds[1]
    end

    local function jump_to(d)
      if not d then return end
      if vim.api.nvim_get_current_buf() ~= d.bufnr then
        local window
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == d.bufnr then
            window = win; break
          end
        end
        if window then
          vim.api.nvim_set_current_win(window)
        else
          vim.cmd('edit ' .. vim.api.nvim_buf_get_name(d.bufnr))
        end
      end
      local lines = vim.api.nvim_buf_line_count(d.bufnr)
      vim.api.nvim_win_set_cursor(0, { math.min(d.lnum + 1, lines), d.col })
      vim.schedule(function()
        vim.diagnostic.open_float(d.bufnr, { scope = 'cursor', focus = false })
      end)
    end

    local sev_list = type(severities) == 'table' and severities or {}
    local cur_buf = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    for _, sev in ipairs(sev_list) do
      local d = next_in_buffer(sev, cur_buf, pos[1], pos[2])
      if d then return jump_to(d) end
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and b ~= cur_buf then
          local d2 = next_in_buffer(sev, b, nil, nil)
          if d2 then return jump_to(d2) end
        end
      end
    end
  end),
}

-- WHEN ----------------------------------------------------------------------------------------------------------

-- Conditional execution:
--   F.when({lang = 'cpp'}, F.lsp.definition())
--   F.when({lang = {'cpp', 'rust'}}, F.shell('make'))
--   F.when({buffer = 'help'}, function() vim.cmd('q') end)
F.when = function(cond, action)
  return function()
    local ft = vim.bo.filetype

    -- Check language/filetype condition
    if cond.lang then
      local langs = type(cond.lang) == 'table' and cond.lang or {cond.lang}
      local matched = false
      for _, lang in ipairs(langs) do
        if ft == lang then
          matched = true
          break
        end
      end
      if not matched then return end
    end

    -- Check buffer type condition
    if cond.buffer and vim.bo.buftype ~= cond.buffer then
      return
    end

    -- Execute action
    return action()
  end
end

-- TREE -----------------------------------------------------------------------------------------------------------

F.tree = {
  toggle = function()
    local ok, api = pcall(require, 'nvim-tree.api')
    if not ok then
      vim.notify('nvim-tree not available', vim.log.levels.WARN)
      return
    end
    local visible = api.tree.is_visible()
    if not visible then
      local bufpath = vim.fn.expand('%:p')
      local isdir = bufpath ~= '' and vim.fn.isdirectory(bufpath) == 1
      -- If we're currently editing a directory buffer, temporarily show hidden files
      if isdir then
        api.tree.toggle_hidden_filter()
        _G.F._tree_reset_hidden_on_close = true
      end
      api.tree.open()
    else
      -- If we temporarily enabled hidden files on open, restore default hidden state on close
      if _G.F._tree_reset_hidden_on_close then
        local ok2, api2 = pcall(require, 'nvim-tree.api')
        if ok2 then api2.tree.toggle_hidden_filter() end
        _G.F._tree_reset_hidden_on_close = nil
      end
      api.tree.close()
    end
  end,
}

-- SETUP ---------------------------------------------------------------------------------------------------------

-- Setup a project with the given `init.lua` path and `config`
local function setup_project(state, init, config)
  -- Setup per-project state
  if not state.projects[init] then
    state.projects[init] = {}
  end
  local project = state.projects[init]

  if not project.config then
    project.config = config
  end

  -- Setup keybinds
  if not project.keymaps then
    project.keymaps = {}
  else
    -- Clear existing keybinds
    for _, keymap in ipairs(project.keymaps) do
      pcall(vim.keymap.del, keymap.modes, keymap.key)
    end
  end
  -- Supported formats for `config.keys`:
  --   [{ 'Description',            '<key>' }] = action  -- defaults to {'n'}
  --   [{ 'Description', {'i','n'}, '<key>' }] = action
  if config.keys then
    for binding, action in pairs(config.keys) do

      if type(binding) ~= "table" or #binding < 2 or #binding > 3 then
        error("Invalid keybind: expecting {'desc', 'key'} or {'desc', {'i', 'n', ...}, 'key'}")
      end

      local desc, modes, key
      if #binding == 2 then
        desc, modes, key = binding[1], {"n"},      binding[2]
      elseif #binding == 3 then
        desc, modes, key = binding[1], binding[2], binding[3]
      end

      -- vim.keymap.set doesn't like metatable with __call
      if type(action) == "table" then
        local mt = getmetatable(action)
        action = mt.__call
      end

      vim.keymap.set(modes, key, action, { silent = true, desc = desc })
      table.insert(project.keymaps, { modes = modes, key = key })
    end
  end
end

local function setup_global()
  -- Initialize lua-global state store
  if not _G.F then
    _G.F = F
    _G.F.state = {}
  end
  local state = _G.F.state

  -- Call setup.lua once
  if not state.setup then
    require('setup').setup()
    state.setup = true
  end

  -- Initialize project tracking
  if not state.projects then
    state.projects = {}

    -- Load projects when editing an init.lua
    vim.api.nvim_create_autocmd('BufWritePost', {
      pattern = {
        '*/.config/nvim/init.lua',
        '*/.nvim/init.lua',
      },
      callback = function(args)
        local init = args.file
        if init == '' then return end

        local dirs = F.project.all(init)
        for _, dir in ipairs(dirs) do
          local project_init = dir .. '/.nvim/init.lua'
          if vim.fn.filereadable(project_init) == 1 then
            vim.cmd('source ' .. project_init)
            vim.notify('Loaded ' .. project_init)
          end
        end

        vim.cmd('source ' .. init)
        vim.notify('Loaded ' .. init)
      end,
    })

    -- Load parent projects when editing a new file
    local cache = {}
    vim.api.nvim_create_autocmd('BufEnter', {
      callback = function(args)
        local path = args.file
        if path == '' then return end

        local projects = cache[path]
        if not projects then
          projects = F.project.all(path)
          cache[path] = projects
        end
        if #projects == 0 then return end

        for _, dir in ipairs(projects) do
          local init = dir .. '/.nvim/init.lua'
          if not state.projects[init] and vim.fn.filereadable(init) == 1 then
            vim.cmd('source ' .. init)
            vim.notify('Loaded ' .. init)
          end
        end
      end
    })
  end

  return state
end

-- Public setup entrypoint
F.setup = function(config)
  local state = setup_global()

  -- Setup project using path of calling init.lua file
  local init = debug.getinfo(2, 'S').short_src
  setup_project(state, init, config)
end

return F
