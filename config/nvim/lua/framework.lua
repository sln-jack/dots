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
F.cwd = function()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname ~= "" then
    return vim.fn.fnamemodify(bufname, ':p:h')
  else
    return vim.fn.getcwd()
  end
end

-- Get current visual mode selection or nil.
F.selection = function()
  -- Ensure some kind of visual mode
  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    return nil
  end

  -- Exit and reselect to update < and > marks
  vim.cmd('normal! gv')
  local pos0 = vim.fn.getpos("'<")
  local pos1 = vim.fn.getpos("'>")
  local region = vim.fn.getregionpos(pos0, pos1, { type = mode, inclusive = true, eol = true })

  local lines = {}
  for _, seg in ipairs(region) do
    local start_pos, end_pos = seg[1], seg[2]
    -- local bufnr = start_pos[1]
    local line = start_pos[2]
    local col0 = start_pos[3]
    local col1 = end_pos[3]

    local text = vim.fn.getline(line)
    if col0 > 0 and col1 > 0 and #text > 0 then
      table.insert(lines, text:sub(col0, col1))
    else
      table.insert(lines, "")
    end
  end
  return table.concat(lines, '\n')
end

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
    local tb = require('telescope.builtin')

    opts = opts or {}
    local dir = call(opts.dir) or F.cwd()

    local args = {}
    if opts.depth then
      table.insert(args, '--max-depth')
      table.insert(args, tostring(opts.depth))
    end
    if opts.hidden     then table.insert(args, '--hidden') end
    if opts.gitignored then table.insert(args, '--no-ignore') end

    tb.find_files({
      prompt_title = string.format('Files (%s) %s', dir, table.concat(args, ' ')),
      find_command = vim.tbl_extend('force', {'fd', '--type', 'f'}, args),
      cwd          = vim.fn.expand(dir),
    })
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
    local dir = call(opts.dir) or F.cwd()

    local args = {}
    if opts.depth then
      table.insert(args, '--max-depth')
      table.insert(args, tostring(opts.depth))
    end
    if opts.hidden     then table.insert(args, '--hidden') end
    if opts.gitignored then table.insert(args, '--no-ignore') end

    tb.find_files({
      prompt_title    = string.format('Dirs (%s) %s', dir, table.concat(args, ' ')),
      cwd             = vim.fn.expand(dir),
      find_command    = vim.tbl_extend('force', {'fd', '--type', 'd'}, args),
      attach_mappings = function(_, map)
        -- Bind <enter> to cd and edit the selected dir
        map('i', '<cr>', function(prompt_bufnr)
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          vim.cmd('cd ' .. entry.path)
          vim.cmd('edit .')
        end)
        return true
      end
    })
  end),

  -- Buffer picker
  buffer = function()
    require('telescope.builtin').buffers()
  end,

  notification = function()
    require('telescope').extensions.notify.notify()
  end,
}

-- GREP ------------------------------------------------------------------------------------------------------

-- Grep files or current buffer
-- opts:
--   * dir: directory to search (omit to grep current buffer)
--   * hidden: search hidden files
--   * gitignored: search gitignored files
F.grep = lazy(function(opts)
  local t = require('telescope')
  local tb = require('telescope.builtin')

  opts = opts or {}
  local dir = call(opts.dir)
  local selection = F.selection()
  if selection then
    selection = vim.fn.escape(selection, [[\/.*$^~[](){}?+-]])
    local newline = selection:find('\n', 1, true)
    if newline then
      selection = selection:sub(1, newline - 1)
    end
  end

  if not dir then
    tb.current_buffer_fuzzy_find {
      prompt_title = 'Ripgrep (buffer)',
      default_text = selection,
    }
  else
    local args = {}
    if opts.hidden     then table.insert(args, '--hidden') end
    if opts.gitignored then table.insert(args, '--no-ignore') end

    t.extensions.live_grep_args.live_grep_args({
      prompt_title    = string.format('Ripgrep (%s) %s', dir, table.concat(args, ' ')),
      cwd             = vim.fn.expand(dir),
      default_text    = selection,
      additional_args = args,
    })
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
  -- Hover (show docs, signature, etc.)
  hover = function()
    vim.lsp.buf.hover()
  end,

  -- Rename symbol
  rename = function()
    require('live-rename').rename { insert = true }
  end,

  -- Go to definition
  definition = function()
    require('telescope.builtin').lsp_definitions()
  end,

  -- Find references
  references = function()
    require('telescope.builtin').lsp_references()
  end,

  -- Find symbol
  symbols = function()
    require('telescope.builtin').lsp_dynamic_workspace_symbols()
  end,

  -- Implementations
  impls = function()
    require('telescope.builtin').lsp_implementations()
  end,

  -- Type definitions
  typedefs = function()
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

  -- Toggle inlay hints
  toggle_hints = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
    vim.lsp.inlay_hint.enable(not enabled, { bufnr = bufnr })
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

F.dap = {
  start = F.cmd.with(':DapNew'),
  stop = function() require('dap').terminate() end,
  detach = function()
    local dap = require('dap')
    dap.disconnect({restart = false, terminateDebugee = false})
    dap.close()
  end,

  continue = function() require('dap').continue() end,
  continue_to_cursor = function() require('dap').run_to_cursor() end,

  step_over = function() require('dap').step_over() end,
  step_into = function() require('dap').step_into() end,
  step_out  = function() require('dap').step_out()  end,

  breakpoint = function() require('dap').toggle_breakpoint() end,
  breakpoint_condition = function()
    local cond = vim.fn.input('Condition: ')
    require('dap').set_breakpoint(cond)
  end,

  repl = function() require('dap').repl.toggle() end,
}


-- GIT -----------------------------------------------------------------------------------------------------------

-- Copy web permalink to selected line(s).
--   * branch: copy link to a specific branch
F.git = {
  ui = lazy(function(opts)
    require('neogit').open(opts or {})
  end),

  permalink = lazy(function(opts)
    opts = opts or {}

    local file = vim.fn.expand('%')
    local root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    local relpath = file:gsub('^' .. vim.pesc(root .. '/'), '')

    local branch = opts.branch or vim.fn.systemlist('git rev-parse --abbrev-ref HEAD')[1] or 'main'
    local remote = vim.fn.systemlist('git config --get remote.origin.url')[1]

    local line0, line1
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
      line0 = vim.fn.line("v")
      line1 = vim.fn.line(".")
    else
      line0 = vim.fn.line('.')
      line1 = line0
    end
    if line0 > line1 then
      line0, line1 = line1, line0
    end

    if remote:match('github.com') then
      local baseurl = remote
        :gsub('^git@github%.com:', 'https://github.com/')
        :gsub('%.git$', '')
        :gsub('^https://github%.com/', 'https://github.com/')

      local linespec = line0 == line1
        and string.format('#L%d', line0)
        or string.format('#L%d-L%d', line0, line1)

      local url = string.format('%s/blob/%s/%s%s', baseurl, branch, relpath, linespec)

      vim.fn.setreg('+', url)
      vim.notify(url)
    else
      vim.notify('Unsupported remote: ' .. remote, vim.log.levels.WARN)
    end
  end)
}

-- WHEN ----------------------------------------------------------------------------------------------------------

-- Conditional execution:
--   F.when({lang = 'cpp'}, F.lsp.definition())
--   F.when({lang = {'cpp', 'rust'}}, F.shell('make'))
--   F.when({buffer = 'help'}, function() vim.cmd('q') end)
F.when = function(cond, action)
  return setmetatable({}, {
    __call = action,
    __cond = cond,
  })
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
  project.config = config

  -- Setup fresh keybinds
  if not project.keymaps then
    project.keymaps = {}
  else
    for _, keymap in ipairs(project.keymaps) do
      pcall(vim.keymap.del, keymap.modes, keymap.key)
    end
  end
  -- Setup fresh autocmds
  if not project.autocmds then
    project.autocmds = {}
  else
    for _, autocmd in ipairs(project.autocmds) do
      pcall(vim.api.nvim_del_autocmd, autocmd)
    end
  end

  if config.keys then
    for binding, action in pairs(config.keys.binds or {}) do

      if type(binding) ~= "table" or #binding < 2 or #binding > 3 then
        error("Invalid keybind: expecting {'desc', 'key'} or {'desc', {'i', 'n', ...}, 'key'}")
      end

      -- Formats for `config.keys.binds`:
      --   [{ 'Description',            '<key>' }] = action  -- defaults to {'n'}
      --   [{ 'Description', {'i','n'}, '<key>' }] = action
      local desc, modes, key
      if #binding == 2 then
        desc, modes, key = binding[1], {"n"},      binding[2]
      elseif #binding == 3 then
        desc, modes, key = binding[1], binding[2], binding[3]
      end

      -- Remap key aliases
      for alias, replacement in pairs(config.keys.aliases or {}) do
        key = key:gsub(alias, replacement)
      end

      -- Handle metatable from lazy() and when()
      local cond
      if type(action) == "table" then
        local mt = getmetatable(action)
        action = mt.__call
        cond = mt.__cond
      end

      if cond then
        -- Conditional keybinds get a FileType autocmd to determine whether apply to each buffer
        local patterns = type(cond.lang) == 'table' and cond.lang or { cond.lang or '*' }
        local autocmd = vim.api.nvim_create_autocmd('FileType', {
          pattern = patterns,
          callback = function(ev)
            if cond.buffer and vim.bo[ev.buf].buftype ~= cond.buffer then
              return
            end
            vim.keymap.set(modes, key, action, { buffer = ev.buf, silent = true, desc = desc })
          end,
        })
        table.insert(project.autocmds, autocmd)
        -- Not stored in project.keymaps since they're ephemeral anyways
      else
        -- Unconditional binds are set globally
        vim.keymap.set(modes, key, action, { silent = true, desc = desc })
        table.insert(project.keymaps, { modes = modes, key = key })
      end
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
