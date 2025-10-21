local F = {}

-- UTILITIES ------------------------------------------------------------------------------------------------------

-- Makes a function lazy-capable with .with for deferred evaluation
local function lazy(fn)
  return setmetatable({
    with = function(...)
      local args = { ... }
      return function()
        local res = fn(unpack(args))
        if type(res) == 'function' then
          return res()
        end
        return res
      end
    end,
  }, {
    __call = function(_, ...)
      return fn(...)
    end,
  })
end

-- Evaluates an arg that's either a function/callable or a plain value
local function is_callable(x)
  if type(x) == 'function' then return true end
  if type(x) == 'table' then
    local mt = getmetatable(x)
    return mt and mt.__call ~= nil
  end
  return false
end

function F.eval(x)
  return is_callable(x) and x() or x
end

-- CONTEXT -------------------------------------------------------------------------------------------------------

-- Get current working directory (buffer's directory if editing a file, otherwise vim's cwd)
F.cwd = lazy(function()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname ~= "" then
    return vim.fn.fnamemodify(bufname, ':p:h')
  end
  return vim.fn.getcwd()
end)

-- PROJECT -------------------------------------------------------------------------------------------------------

F.project = {
  -- Find closest .nvim/ directory (current project)
  dir = lazy(function()
    local path = vim.fn.expand('%:p:h')
    local nvim_dir = vim.fs.find('.nvim', { path = path, upward = true, type = 'directory' })[1]
    return nvim_dir and vim.fs.dirname(nvim_dir) or vim.fn.getcwd()
  end),

  -- Find top-level git root
  root = lazy(function()
    local path = vim.fn.expand('%:p:h')
    local git = vim.fs.find('.git', { path = path, upward = true })[1]
    return git and vim.fs.dirname(git) or F.project.dir()
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

-- PICK ----------------------------------------------------------------------------------------------------------

F.pick = {
  -- File picker
  -- opts:
  --   * dir: directory to search (default cwd)
  --   * hidden: include hidden files
  --   * no_ignore: include gitignored files
  file = lazy(function(opts)
    opts = opts or {}
    return function()
      local telescope_opts = {}
      -- Evaluate dir lazily if it's a function
      local dir = F.eval(opts.dir)
      -- Auto-expand paths
      if dir then 
        telescope_opts.cwd = vim.fn.expand(dir)
        telescope_opts.prompt_title = string.format('Files (%s)', telescope_opts.cwd)
      else
        telescope_opts.prompt_title = string.format('Files (%s)', vim.fn.getcwd())
      end

      -- Build fd command based on options (depth/hidden/no_ignore)
      if opts.hidden or opts.no_ignore or opts.depth then
        local cmd = { 'fd', '--type', 'f' }
        if opts.hidden then table.insert(cmd, '--hidden') end
        if opts.no_ignore then table.insert(cmd, '--no-ignore') end
        if opts.depth then
          table.insert(cmd, '--max-depth')
          table.insert(cmd, tostring(opts.depth))
        end
        telescope_opts.find_command = cmd
      end

      require('telescope.builtin').find_files(telescope_opts)
    end
  end),

  -- Directory picker (lists directories only)
  -- opts:
  --   * dir: directory to search (default cwd)
  --   * hidden: include hidden directories
  --   * no_ignore: include gitignored directories
  dir = lazy(function(opts)
    opts = opts or {}
    return function()
      local tb = require('telescope.builtin')
      local actions = require('telescope.actions')
      local state = require('telescope.actions.state')
      local telescope_opts = {}
      local base = F.eval(opts.dir)
      if base then telescope_opts.cwd = vim.fn.expand(base) end
      local search_root = telescope_opts.cwd or vim.fn.getcwd()
      telescope_opts.prompt_title = string.format('Dirs (%s)', search_root)
      local cmd = { 'fd', '--type', 'd' }
      if opts.hidden then table.insert(cmd, '--hidden') end
      if opts.no_ignore then table.insert(cmd, '--no-ignore') end
      local depth = opts.depth or 1
      if depth then
        table.insert(cmd, '--max-depth')
        table.insert(cmd, tostring(depth))
      end
      telescope_opts.find_command = cmd
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
    end
  end),

  -- Buffer picker
  buffer = function()
    return function()
      require('telescope.builtin').buffers()
    end
  end,
}

-- GREP ----------------------------------------------------------------------------------------------------------

-- Grep files or current buffer
-- opts:
--   * dir: directory to search (omit to grep current buffer)
--   * hidden: search hidden files
--   * no_ignore: search gitignored files
F.grep = lazy(function(opts)
  opts = opts or {}
  return function()
    -- Evaluate dir lazily if it's a function
    local dir = F.eval(opts.dir)
    -- Auto-expand paths
    if dir then
      dir = vim.fn.expand(dir)
    end

    -- Default to current buffer if no dir specified
    if not dir then
      require('telescope.builtin').current_buffer_fuzzy_find { prompt_title = 'Grep (buffer)' }
    else
      local telescope_opts = { cwd = dir, prompt_title = string.format('Grep (%s)', dir) }

      -- Build rg args based on options
      if opts.hidden or opts.no_ignore then
        telescope_opts.additional_args = function()
          local args = {}
          if opts.hidden then table.insert(args, '--hidden') end
          if opts.no_ignore then table.insert(args, '--no-ignore') end
          return args
        end
      end

      require('telescope.builtin').live_grep(telescope_opts)
    end
  end
end)

-- ACTIONS -------------------------------------------------------------------------------------------------------

-- Run shell command
F.shell = lazy(function(cmd)
  return function() vim.cmd('!' .. cmd) end
end)

-- Edit file
F.edit = lazy(function(path)
  return function() vim.cmd.edit(vim.fn.expand(F.eval(path))) end
end)

-- Change directory
F.cd = lazy(function(path)
  return function() vim.cmd.cd(vim.fn.expand(F.eval(path))) end
end)

-- Run vim command (caller should include : if needed, e.g. ':Yazi')
F.cmd = lazy(function(cmd)
  return function()
    vim.cmd(cmd)
  end
end)

-- LSP -----------------------------------------------------------------------------------------------------------

F.lsp = {
  -- Rename symbol
  rename = function() 
    return function() require('live-rename').map { insert = true } end
  end,

  -- Go to definition
  definition = function() 
    return function() require('telescope.builtin').lsp_definitions() end
  end,

  -- Find references
  references = function() 
    return function() require('telescope.builtin').lsp_references() end
  end,

  -- Workspace symbols
  symbols = function() 
    return function() require('telescope.builtin').lsp_dynamic_workspace_symbols() end
  end,

  -- Document symbols
  doc_symbols = function()
    return function() require('telescope.builtin').lsp_document_symbols() end
  end,

  -- Implementations
  implementations = function()
    return function() require('telescope.builtin').lsp_implementations() end
  end,

  -- Type definitions
  types = function()
    return function() require('telescope.builtin').lsp_type_definitions() end
  end,

  -- Code action
  action = function()
    return vim.lsp.buf.code_action
  end,

  -- Format buffer
  format = function()
    return function()
      require('conform').format { async = true, lsp_format = 'fallback' }
    end
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

-- Conditional execution
-- Examples:
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

-- Main initialization - handles setup and reload logic
F.setup = function(config)
  -- Initialize global state
  _G.F = _G.F or {}

  -- Bootstrap setup (only runs once)
  if not _G.F.initialized then
    require('setup').setup()
    _G.F.initialized = true
  end

  -- Clear existing keymaps on reload
  if _G.F.keymaps then
    for _, keymap in ipairs(_G.F.keymaps) do
      pcall(vim.keymap.del, keymap.mode, keymap.lhs)
    end
  end
  _G.F.keymaps = {}

  -- Apply keybindings from config
  if config.keys then
    for binding, action in pairs(config.keys) do
      local modes, key, desc
      -- Supported forms:
      --   ['<key>'] = action
      --   [{ {'i','n'}, '<key>' }] = action
      --   [{ 'i','n','<key>' }] = action
      --   [{ 'Description', '<key>' }] = action        -- default normal mode
      --   [{ 'Description', {'i','n'}, '<key>' }] = action
      if type(binding) == 'table' then
        if type(binding[1]) == 'string' then
          desc = binding[1]
          if type(binding[2]) == 'table' and binding[3] then
            modes = binding[2]
            key = binding[3]
          else
            modes = 'n'
            key = binding[2]
          end
        elseif type(binding[1]) == 'table' and binding[2] then
          modes = binding[1]
          key = binding[2]
        else
          key = binding[#binding]
          if #binding > 1 then
            modes = {}
            for i = 1, #binding - 1 do modes[i] = binding[i] end
          else
            modes = 'n'
          end
        end
      else
        modes = 'n'
        key = binding
      end
      vim.keymap.set(modes, key, action, { silent = true, desc = desc })
      table.insert(_G.F.keymaps, { mode = modes, lhs = key })
    end
  end


  -- Load project-specific config
  local project = F.project.load()
  if project.keys then
    for key, action in pairs(project.keys) do
      vim.keymap.set('n', key, action, { desc = 'Project: ' .. key })
      table.insert(_G.F.keymaps, { mode = 'n', lhs = key })
    end
  end
  if project.setup then
    project.setup()
  end

  -- Setup auto-reload
  if not _G.F.reload_setup then
    local reload = function()
      package.loaded.framework = nil
      package.loaded.init = nil
      vim.cmd('source ' .. vim.fn.stdpath('config') .. '/init.lua')
      vim.notify('Config reloaded')
    end

    vim.api.nvim_create_autocmd('BufWritePost', {
      pattern = {
        vim.fn.stdpath('config') .. '/init.lua',
        vim.fn.stdpath('config') .. '/framework.lua',
        '*/.nvim/init.lua',
      },
      callback = reload
    })

    vim.api.nvim_create_user_command('Reload', reload, {})
    _G.F.reload_setup = true
  end
end

return F
