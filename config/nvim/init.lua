---@diagnostic disable redefineHidden d-local

---------  TODO: ---------------------------------------------------------------------------------------------

-- Treesitter incremental selection ----> `:help nvim-treesitter-incremental-selection-mod`
-- Treesitter textobjects ----> https://github.com/nvim-treesitter/nvim-treesitter-textobjects
-- nerd font picker: copy this ----> https://github.com/davidmh/cmp-nerdfonts/blob/main/lua/cmp_nerdfonts/source.lua

-- Check these kickstart plugins?
-- require 'kickstart.plugins.debug',
-- require 'kickstart.plugins.indent_line',
-- require 'kickstart.plugins.lint',
-- require 'kickstart.plugins.autopairs',
-- require 'kickstart.plugins.neo-tree',
-- require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps
--
-- Try kickstart `:checkhealth` for more info.
--

--[[----  NOTE: Reminders ------------------------------------------------------------------------------------

  * `gv` to reselect last visual mode selection

]]

--------  NOTE: Keybinds -------------------------------------------------------------------------------------

_G.asm = {
  files = {},   -- id -> path
  locs = {},    -- line -> {file, line, col}
  funcs = {},   -- {name, start, stop}
  branches = {},-- {line, target}
  labels = {},  -- label -> line
}

------------------------------------------------------------
-- analysis pass: gather files, locs, funcs, branches
------------------------------------------------------------
function _G.asm_analyze()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  asm.files, asm.locs, asm.funcs, asm.branches, asm.labels = {}, {}, {}, {}, {}

  local current_funcs = {}

  for i, l in ipairs(lines) do
    local id, dir, name = l:match("%.file%s+(%d+)%s+\"([^\"]+)\"%s+\"([^\"]+)\"")
    if id then
      asm.files[tonumber(id)] = dir .. "/" .. name
    end

    local fid, ln, col = l:match("%.loc%s+(%d+)%s+(%d+)%s+(%d+)")
    if fid then
      asm.locs[i] = { file = asm.files[tonumber(fid)], line = tonumber(ln), col = tonumber(col) }
    end

    local begin = l:match("; %+-%- Begin function ([%w_]+)")
    if begin then
      table.insert(current_funcs, { name = begin, start = i })
    end
    if l:match("; %+-%- End function") and #current_funcs > 0 then
      local fn = table.remove(current_funcs)
      fn.stop = i
      table.insert(asm.funcs, fn)
    end

    local lbl = l:match("^(L[%w_]+):")
    if lbl then
      asm.labels[lbl] = i
    end

    local target = l:match("%s+b%.%w+%s+(L[%w_]+)")
    if target then
      table.insert(asm.branches, { line = i, target = target })
    end
  end

  vim.notify(("asm analyzed: %d files, %d locs, %d funcs, %d branches"):format(
    vim.tbl_count(asm.files),
    vim.tbl_count(asm.locs),
    #asm.funcs,
    #asm.branches
  ))
end

------------------------------------------------------------
-- 1. inline source preview for `.loc`
------------------------------------------------------------
function _G.asm_inline_src()
  local ns = vim.api.nvim_create_namespace("asm_src")
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

  for i, loc in pairs(asm.locs) do
    if loc.file and loc.file:match("src/") then
      local buf = vim.fn.bufnr(loc.file, true)
      if buf ~= -1 then
        local src = vim.fn.getbufline(buf, loc.line)[1]
        if src then
          vim.api.nvim_buf_set_extmark(0, ns, i - 1, 0, {
            virt_text = {{src, "Comment"}},
            virt_text_pos = "right_align",
          })
        end
      end
    end
  end
  vim.notify("inline src added")
end

------------------------------------------------------------
-- 2. function guides
------------------------------------------------------------
function _G.asm_function_guides()
  local ns = vim.api.nvim_create_namespace("asm_fn")
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
  for _, fn in ipairs(asm.funcs) do
    vim.api.nvim_buf_set_extmark(0, ns, fn.start - 1, 0, {
      virt_text = {{"│ " .. fn.name .. "()", "Type"}},
    })
    if fn.stop then
      vim.api.nvim_buf_set_extmark(0, ns, fn.stop - 1, 0, {
        virt_text = {{"└──── " .. fn.name, "Type"}},
      })
    end
  end
  vim.notify("function guides drawn")
end

------------------------------------------------------------
-- 3. branch arrows
------------------------------------------------------------
function _G.asm_branch_arrows()
  local ns = vim.api.nvim_create_namespace("asm_br")
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
  for _, br in ipairs(asm.branches) do
    vim.api.nvim_buf_set_extmark(0, ns, br.line - 1, 0, {
      virt_text = {{ "→ " .. br.target, "Function" }},
      virt_text_pos = "eol",
    })
  end
  for lbl, ln in pairs(asm.labels) do
    vim.api.nvim_buf_set_extmark(0, ns, ln - 1, 0, {
      virt_text = {{ "◀", "Function" }},
      virt_text_pos = "eol",
    })
  end
  vim.notify("branch arrows added")
end

------------------------------------------------------------
-- simple orchestrator
------------------------------------------------------------
function _G.asm_refresh()
  asm_analyze()
  asm_function_guides()
  asm_branch_arrows()
  asm_inline_src()
end

-- <space> is the leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local lib = require('lib')

local bind = lib.bind
local Keymaps = {
  Global = function()
    bind('Save', '', '<D-s>', ':w<cr>')

    bind('Line start',  'i', '<C-a>', '<C-o>0')
    bind('Line end',    'i', '<C-e>', '<C-o>$')
    bind('Delete line', 'i', '<C-k>', '<C-o>D')

    bind('Yazi', 'n', '<leader>y', '<cmd>Yazi<cr>')
  end,

  Windowing = function()
    bind('Quit',          {'i', 'n'}, '<M-q>',   '<cmd>q<cr>')
    bind('Save and Quit', {'i', 'n'}, '<M-S-q>', '<cmd>wq<cr>')

    bind('Split up/down',   'n', '<M-->', ':split<cr>')
    bind('Split side/side', 'n', '<M-=>', ':vsplit<cr>')

    bind('Focus left',  'n', '<M-h>', '<C-w><C-h>')
    bind('Focus right', 'n', '<M-l>', '<C-w><C-l>')
    bind('Focus down',  'n', '<M-j>', '<C-w><C-j>')
    bind('Focus up',    'n', '<M-k>', '<C-w><C-k>')

    bind('Move left',  'n', '<M-S-h>', '<C-w>H')
    bind('Move right', 'n', '<M-S-l>', '<C-w>L')
    bind('Move down',  'n', '<M-S-j>', '<C-w>J')
    bind('Move up',    'n', '<M-S-k>', '<C-w>K')

    bind('Resize up',    'n', '<M-w>', function() require('smart-splits').resize_up() end)
    bind('Resize down',  'n', '<M-s>', function() require('smart-splits').resize_down() end)
    bind('Resize left',  'n', '<M-a>', function() require('smart-splits').resize_left() end)
    bind('Resize right', 'n', '<M-d>', function() require('smart-splits').resize_right() end)

    -- Cmd-+/- to zoom font, Cmd-= to reset (Neovide only)
    if vim.g.neovide then
      local scale = function(func)
        return function() vim.g.neovide_scale_factor = func(vim.g.neovide_scale_factor) end
      end
      bind('Zoom in',    {'n', 'i'}, '<D-=>', scale(function(x) return x + 0.1 end))
      bind('Zoom out',   {'n', 'i'}, '<D-->', scale(function(x) return x - 0.1 end))
      bind('Zoom reset', {'n', 'i'}, '<D-+>', scale(function()  return 1.0     end))
    end
  end,

  Vim = function()
    bind('Re-yank original selection after paste', 'x', 'p', 'pgvy')
    bind('Clear search highlight', 'n', '<Esc>', '<cmd>nohlsearch<cr>')
  end,

  Telescope = function(builtin, actions, state)
    bind('Resume Search',      'n', '<leader>sr', builtin.resume)
    bind('Search Telescope',   'n', '<leader>ss', builtin.builtin)
    bind('Search Help',        'n', '<leader>sh', builtin.help_tags)
    bind('Search Keymaps',     'n', '<leader>sk', builtin.keymaps)
    bind('Search Word',        'n', '<leader>sw', builtin.grep_string)
    bind('Search Diagnostics', 'n', '<leader>sq', builtin.diagnostics)

    -- Buffers / files
    bind('Goto Buffer', 'n', '<leader>-', builtin.buffers)
    bind('Goto File (cwd)', 'n', '<leader>F', builtin.find_files)
    bind('Goto File', 'n', '<leader>f', function()
      local root = lib.project_root()
      builtin.find_files {
        prompt_title = 'Files (' .. vim.fn.fnamemodify(root, ':~') .. ')',
        cwd = root,
      }
    end)
    bind('Goto File (hidden)', 'n', '<leader>g', function()
      local root = lib.project_root()
      builtin.find_files {
        prompt_title = 'Files (' .. vim.fn.fnamemodify(root, ':~') .. ')',
        cwd = root,
        find_command = { 'fd', '-I' }
      }
    end)
    bind('Edit Prev File', 'n', '<leader><tab>', '<cmd>edit #<cr>')
  
    -- Projects and dotfiles
    bind('Edit TODO.md', 'n', '<leader>pt', ':vsplit ~/notes/TODO.md<cr>')
    bind('Edit Note',    'n', '<leader>pn', function()
      builtin.find_files {
        prompt_title = 'Dotfiles',
        cwd = vim.fn.expand "~/notes",
      }
    end)

    bind('Edit scratch',  'n', '<leader>ps', '<cmd>new<cr>')
    bind('Edit init.lua', 'n', '<leader>pc', function() vim.cmd.edit(vim.fn.stdpath('config') .. '/init.lua') end)
    bind('Edit Dotfiles', 'n', '<leader>pd', function()
      builtin.find_files {
        prompt_title = 'Dotfiles',
        cwd = vim.fn.expand "~/code/dots",
      }
    end)
    bind("Reload Dotfiles", "n", "<leader>pr", function()
      local Job = require("plenary.job")
      local buf = lib.popup_buf(100, 20)
      Job:new({
        command = "bash",
        args = { vim.fn.expand("~/code/dots/bootstrap.sh") },
        on_stdout = function(_, line) vim.schedule(function() lib.append_buf(buf, line) end) end,
        on_stderr = function(_, line) vim.schedule(function() lib.append_buf(buf, line) end) end,
      }):start()
    end)
    bind('Goto Project', 'n', '<leader>pp', function()
      local root = '~/code'
      builtin.find_files {
        prompt_title = 'Projects (' .. root .. ')',
        cwd = vim.fn.expand(root),
        find_command = { 'fd', '--type', 'd', '--max-depth', '1' },
        attach_mappings = function(_, map)
          map('i', '<cr>', function(prompt_bufnr)
            local entry = state.get_selected_entry()
            actions.close(prompt_bufnr)
            vim.cmd('cd ' .. entry.path)
            vim.cmd 'edit .'
          end)
          return true
        end,
      }
    end)

    -- Grep
    bind('Grep Buffer', 'n', '<leader>,', function()
      builtin.current_buffer_fuzzy_find { prompt_title = 'Grep Buffer' }
    end)
    bind('Grep Cwd', 'n', '<leader>.', function()
      builtin.live_grep { prompt_title = 'Grep Cwd' }
    end)
    bind('Grep Project', 'n', '<leader>/', function()
      local root = lib.project_root()
      builtin.live_grep {
        prompt_title = 'Grep Project (' .. vim.fn.fnamemodify(root, ':~') .. ')',
        cwd = root,
      }
    end)

    bind('Grep Project Hidden', 'n', '<leader>?', function()
      local root = lib.project_root()
      builtin.live_grep {
        prompt_title = 'Grep Project Hidden (' .. vim.fn.fnamemodify(root, ':~') .. ')',
        cwd = root,
        additional_args = function()
          return { '--hidden', '--glob', '!.git/*' }
        end,
      }
    end)
  end,

  Lsp = function(event, supports, bind)
    local tb = require('telescope.builtin')
    bind('Rename',              'n', '<leader>r', require('live-rename').map { insert = true })
    bind('Find Symbol',         'n', '<leader>t', tb.lsp_dynamic_workspace_symbols)
    bind('Code Action',         'n', '<leader>a', vim.lsp.buf.code_action)
    bind('Goto Definition',     'n', '<leader>d', tb.lsp_definitions)
    bind('Goto Implementation', 'n', '<leader>D', tb.lsp_implementations)

    bind('Doc Symbol',      'n', '<leader>ld', tb.lsp_document_symbols)
    bind('Goto References', 'n', '<leader>lr', tb.lsp_references)
    bind('Goto Typedef',    'n', '<leader>lt', tb.lsp_type_definitions)

    bind('Format', 'n', '<leader>lf', function()
      require('conform').format { async = true, lsp_format = 'fallback' }
    end)

    -- Diagnostics list + smart navigation
    bind('Goto Diagnostics', 'n', '<leader>q', tb.diagnostics)
    bind('Next Diagnostic', 'n', '<leader>e', function()
      local function diagnostics(buf, sev)
        local ds = vim.diagnostic.get(buf, { severity = vim.diagnostic.severity[sev] })
        table.sort(ds, function(a, b)
          if a.lnum == b.lnum then return a.col < b.col end
          return a.lnum < b.lnum
        end)
        return ds
      end

      local function next_diagnostic(sev, buf, line, col)
        local ds = diagnostics(buf, sev)
        -- Prioritize diagnostics after the current line
        if line ~= nil then
          for _, d in ipairs(ds) do
            if d.lnum + 1 > line or d.col > col then
              return d
            end
          end
        end
        -- Otherwise return in order
        return ds[1]
      end

      local function jump_to(d)
        if vim.api.nvim_get_current_buf() ~= d.bufnr then
          local window
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win)
              and vim.api.nvim_win_get_buf(win) == d.bufnr then
              window = win
              break
            end
          end
          if window then
              vim.api.nvim_set_current_win(window)
          else
            vim.cmd('edit ' .. vim.api.nvim_buf_get_name(d.bufnr))
          end
        end
        local lines = vim.api.nvim_buf_line_count(d.bufnr)
        -- Ignore failure in case diagnostic is stale
        pcall(vim.api.nvim_win_set_cursor, 0, { math.min(d.lnum + 1, lines), d.col })
        vim.schedule(function()
          vim.diagnostic.open_float(d.bufnr, { scope = 'cursor', focus = false })
        end)
      end


      for _, sev in ipairs({ 'ERROR', 'WARN', 'INFO', 'HINT' }) do
        -- First check current buffer
        local buf  = vim.api.nvim_get_current_buf()
        local pos = vim.api.nvim_win_get_cursor(0)
        local line = pos[1]
        local col = pos[2]
        local d = next_diagnostic(sev, buf, line, col)
        if d then return jump_to(d) end
        -- Then other buffers
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) then
            local d = next_diagnostic(sev, buf, nil, nil)
            if d then return jump_to(d) end
          end
        end
      end
    end)

    vim.keymap.set("v", "<leader>x", function()
      -- get visual selection
      local _, ls, cs = unpack(vim.fn.getpos("'<"))
      local _, le, ce = unpack(vim.fn.getpos("'>"))
      local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, false)
      lines[#lines] = string.sub(lines[#lines], 1, ce)
      lines[1] = string.sub(lines[1], cs)
      local code = table.concat(lines, "\n")

      -- evaluate
      local ok, result = pcall(loadstring(code))
      if not ok then
        vim.print("error:", result)
      else
        vim.print(result)
      end
    end, { desc = "eval selected lua" })

    -- Toggle inlay hints
    if supports(vim.lsp.protocol.Methods.textDocument_inlayHint) then
      bind('Toggle inlay hints', 'n', '<leader>li', function()
        local bufnr = event.buf
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled(bufnr), { bufnr = bufnr })
      end)
    end

    -- Highlight references under cursor
    if supports(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
      local group = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        group = group,
        buffer = event.buf,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = group,
        buffer = event.buf,
        callback = vim.lsp.buf.clear_references,
      })
      vim.api.nvim_create_autocmd('LspDetach', {
        group = group,
        callback = function(ev)
          vim.lsp.buf.clear_references()
          vim.api.nvim_clear_autocmds { group = 'lsp-highlight', buffer = ev.buf }
        end,
      })
    end
  end,

  FileType = {
    [{ 'help', 'man', 'qf', 'lspinfo' }] = function()
      bind('Close buffer', 'n', 'q', '<cmd>q<cr>', { buffer = true })
    end,
  },
}

-------- NOTE: QoL Improvements ------------------------------------------------------------------------------

function QoL()
  -- Live preview of substitutions
  vim.o.inccommand = 'split'
  -- Case-insensitive search unless query includes \C or capital letters
  vim.o.ignorecase = true
  vim.o.smartcase = true
  -- Preserve indentation on wrapped lines
  vim.o.breakindent = true
  -- When we :q with unsaved changes, ask to save instead of failing
  vim.o.confirm = true
  -- Enable mouse input
  vim.o.mouse = 'a'
  -- Sync clipboard with OS. Schedule after `UiEnter` since it increases startup time
  vim.schedule(function()
    vim.o.clipboard = 'unnamedplus'
  end)
  -- Save undo history
  vim.o.undofile = true
  -- Restore cursor position when reopening files (mark ")
  vim.api.nvim_create_autocmd('BufReadPost', {
    callback = function()
      if vim.tbl_contains({ 'gitcommit', 'gitrebase', 'help' }, vim.bo.filetype) then
        return
      end
      vim.cmd 'silent! normal! g`"zz'
    end,
  })

  -- Grab bag of stock-vim-ish QoL
  local mini = {
    'echasnovski/mini.nvim',
    config = function()
      -- Additional a/i motions, such as `vaf` to select a function call
      require('mini.ai').setup { n_lines = 500 }
      -- Additional s motions, such as `sa)` to surround with parens, or `sr"'` to swap quotes
      require('mini.surround').setup { n_lines = 500 }
      -- Comment lines and selection with `gc`
      require('mini.comment').setup {}
      -- Swap function args from single line to multiple with `gS`
      require('mini.splitjoin').setup {}
      -- Align lines with `ga`
      require('mini.align').setup {}
      -- Move lines and selection around with Alt-arrows
      require('mini.move').setup {
        mappings = {
          left = '<M-Left>',
          right = '<M-Right>',
          down = '<M-Down>',
          up = '<M-Up>',
          line_left = '<M-Left>',
          line_right = '<M-Right>',
          line_down = '<M-Down>',
          line_up = '<M-Up>',
        },
      }
      -- Additional operators like `gs` to sort and `gx` to exchange
      require('mini.operators').setup {}
      -- -- Auto-create closing pair when typing ([{"'`
      -- require('mini.pairs').setup {}
    end,
  }

  local splits = {
    'mrjones2014/smart-splits.nvim',
    opts = {}
  }

  -- Detect shiftwidth and tabstop automatically
  local guess_indent = {
    'NMAC427/guess-indent.nvim',
    opts = {},
  }
  -- Indentation defaults
  vim.o.shiftwidth = 4
  vim.o.tabstop = 4
  vim.o.expandtab = true

  -- Display a popup showing which keys do what
  local which_key = {
    'folke/which-key.nvim',
    event = 'VimEnter',
    opts = {
      delay = 0,
      icons = { mappings = true },
    },
  }

  -- Telescope fuzzy finder
  local telescope = {
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
      },
      -- Override vim.ui.select to use telescope (used for LSP code actions, etc.)
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-tree/nvim-web-devicons', enabled = true },
    },
    config = function()
      local telescope = require('telescope')
      local builtin = require('telescope.builtin')
      local actions = require('telescope.actions')
      local state = require('telescope.actions.state')

      telescope.load_extension('fzf')
      telescope.load_extension('ui-select')

      -- See `:help telescope` and `:help telescope.setup()`
      telescope.setup {
        defaults = {
          sorting_strategy = 'ascending',
          layout_config = {
            prompt_position = 'top',
          },
          mappings = {
            i = {
              ['<Esc>'] = require('telescope.actions').close,
              ['<C-enter>'] = 'to_fuzzy_refine',
            },
          },
        },
        pickers = {
          find_files = { follow = true },
        }
      }

      Keymaps.Telescope(builtin, actions, state)
    end,
  }

  return { mini, splits, guess_indent, which_key, telescope }
end

--------  NOTE: Language Support -----------------------------------------------------------------------------

function LangSupport()
  -- Basic syntax highlighting and navigation (non-LSP)
  local treesitter = {
    'nvim-treesitter/nvim-treesitter',
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-context', opts = {} },
      { 'nvim-treesitter/nvim-treesitter-textobjects' },
    },
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs',
    opts = {
      ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
      textobjects = {
        select = {
          enable = true,
          lookahead = true,
          keymaps = {
            ["af"] = "@function.outer",
            ["if"] = "@function.inner",
          },
        },
      },
    },
  }

  -- Autocomplete
  local autocomplete = {
    'saghen/blink.cmp',
    event = 'VimEnter',
    dependencies = {
      'folke/lazydev.nvim',
    },
    build = 'cargo build --release',
    opts = {
      -- Shows function signatures when typing arguments
      signature = { enabled = true },
      -- Use rust implementation of fuzzy matching, warn if it breaks
      fuzzy = { implementation = 'prefer_rust_with_warning' },
      -- Completion sources
      sources = {
        default = { 'lsp', 'path' },
      },
      keymap = {
        preset = 'none',
        ['<tab>'] = { 'accept', 'fallback' },
        ['<Up>'] = { 'select_prev', 'fallback' },
        ['<Down>'] = { 'select_next', 'fallback' },

        ['<C-space>'] = { 'show' },

        ['<C-d>'] = { 'show_documentation' },
        ['<C-j>'] = { 'scroll_documentation_down', 'fallback' },
        ['<C-k>'] = { 'scroll_documentation_up', 'fallback' },

        ['<C-s>'] = { 'show_signature' },
        ['<C-j>'] = { 'scroll_signature_down', 'fallback' },
        ['<C-k>'] = { 'scroll_signature_up', 'fallback' },
      }
    },
  }

  -- Autoformat on save and with <leader> f
  local autoformat = {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- Only format rust, ... on save
        local ty = vim.bo[bufnr].filetype
        if ty == 'rust' then
          return { timeout_ms = 500, lsp_format = 'fallback' }
        else
          return nil
        end
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        rust = { 'rustfmt' },
        -- python = { "isort", "black" },
        -- javascript = { "prettierd", "prettier", stop_after_first = true },
      },
    },
  }

  -- Automatic loading and unloading of .envrc
  local direnv = {
    'NotAShelf/direnv.nvim',
    opts = {
      autoload_direnv = true,
    }
  }

  -- Main LSP setup
  local lsp = {
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Useful status updates for LSP.
      { 'j-hui/fidget.nvim', opts = {} },
      -- Allows extra capabilities provided by blink.cmp
      'saghen/blink.cmp',
      -- Preview results of LSP renames
      {
        'saecki/live-rename.nvim',
        opts = {
          keys = {
            cancel = {
              { 'i', '<Esc>' },
            },
          },
        },
      },
    },
    config = function()

      -- Configure LSP servers (see :help lspconfig-all). Notes:
      --   * cmd (table): Override the default command used to start the server
      --   * filetypes (table): Override the default list of associated filetypes for the server
      --   * capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
      --   * settings (table): Override the default settings passed when initializing the server.

      -- Add blink capabilities (completion) to the defaults
      vim.lsp.config('*', {
        capabilities = require('blink.cmp').get_lsp_capabilities(),
      })

      vim.lsp.enable('clangd')

      -- Note: this will break when editing non-neovim lua files, but there's no clean way to specify per-workspace settings.
      -- See https://github.com/folke/lazydev.nvim for how we can hook nvim internals to emulate it.
      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
              -- neovim require() resolution semantics
              path = {
                'lua/?.lua',
                'lua/?/init.lua',
              },
            },
            workspace = {
              checkThirdParty = false,
              library = {
                -- load symbols for neovim builtins + vim.uv
                vim.env.VIMRUNTIME,
                '${3rd}/luv/library',
              }
            }
          }
        }
      })
      vim.lsp.enable('lua_ls')

      -- Configure keymaps when an LSP starts
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          local supports = function(method)
            ---@diagnostic disable-next-line: param-type-mismatch
            return client and client.supports_method(method, { bufnr = event.buf })
          end
          local lsp_bind = function(desc, mode, keys, action, opts)
            opts = opts or {}
            opts.buffer = event.buf
            bind(desc, mode, keys, action, opts)
          end

          Keymaps.Lsp(event, supports, lsp_bind)
        end,
      })
    end,
  }

  return { treesitter, autocomplete, autoformat, direnv, lsp }
end

--------  NOTE: Cosmetics ------------------------------------------------------------------------------------

function Cosmetics()
  -- Special display for certain whitespace characters
  vim.o.list = true
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
  -- Cursor indicates mode and blinks after inactivity
  vim.opt.guicursor = { 'n-v-c:block', 'i-ci-ve:ver25', 'r-cr:hor20', 'o:hor50', 'a:blinkwait500-blinkoff250-blinkon250' }

  -- Highlight line the cursor is on
  vim.o.cursorline = true
  -- Minimal number of screen lines to keep above and below the cursor.
  vim.o.scrolloff = 10
  -- Relative line numbers in normal mode, absolute in insert mode
  vim.o.number = true
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'BufEnter', 'WinEnter', 'FocusGained' }, {
    callback = function()
      if vim.api.nvim_get_mode().mode ~= 'i' then
        vim.wo.relativenumber = true
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'InsertEnter', 'BufLeave', 'WinLeave', 'FocusLost' }, {
    callback = function()
      vim.wo.relativenumber = false
    end,
  })

  -- Display the cwd in the window title
  vim.opt.title = true
  vim.opt.titlestring = vim.fs.basename(vim.fn.getcwd())
  -- Display a border below the statusline for better horizontal visibility
  vim.o.laststatus = 3
  -- Don't show the mode, since it's already in the status line
  vim.o.showmode = false
  -- Keep the left gutter enabled
  vim.o.signcolumn = 'yes'
  -- Splits open down and right
  vim.o.splitbelow = true
  vim.o.splitright = true

  -- Decrease update time so LSP diagnostics show up faster
  vim.o.updatetime = 250
  -- Decrease mapped sequence wait time
  vim.o.timeoutlen = 300
  -- Sort diagnostics by severity, and auto close the popup
  vim.diagnostic.config({
    float = {
      close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
    },
    severity_sort = true,
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = '',
        [vim.diagnostic.severity.WARN] = '',
        [vim.diagnostic.severity.INFO] = '',
      }
    }
  })

  -- Highlight when yanking text
  vim.api.nvim_create_autocmd('TextYankPost', {
    callback = function()
      vim.hl.on_yank()
    end,
  })

  -- Generate a nice visual divider comment
  vim.api.nvim_create_user_command('Divider', function(opts)
    local comment = vim.bo.commentstring or '//'
    comment = comment:match '^[^%s]+' or comment

    local title = ' ' .. opts.args .. ' '
    local pre_pad = 6
    local post_pad = 110 - pre_pad - #title - #comment
    local divider = comment .. string.rep('-', pre_pad) .. title .. string.rep('-', post_pad)

    vim.api.nvim_put({ divider }, 'l', true, true)
  end, { nargs = 1 })

  -- Color scheme (see `:Telescope colorscheme`)
  local theme = {
    'folke/tokyonight.nvim',
    priority = 1000,
    opts = {
      on_colors = function(colors)
        colors.border = colors.white
      end
    },
    init = function()
      vim.cmd.colorscheme 'tokyonight-night'
    end,
  }

  -- Highlight todo, notes, etc in comments
  local todos = { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } }

  local tree = {
    'nvim-tree/nvim-tree.lua',
    opts = {}
  }

  local yazi = {
    'mikavilpas/yazi.nvim',
    event = 'VeryLazy',
    dependencies = {
      { 'nvim-lua/plenary.nvim', lazy = true },
    },
    opts = {}
  }

  -- Better status line
  local lualine = {
    'nvim-lualine/lualine.nvim',
    opts = {
      options = {
        component_separators = '',
        section_separators = '',
      },
      sections = {
        lualine_a = { 'filename' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = {},
        lualine_x = {},
        lualine_y = { 'progress' },
        lualine_z = { 'location' },
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { 'filename' },
        lualine_x = { 'location' },
        lualine_y = {},
        lualine_z = {},
      },
    },
  }

  -- Add git signs to the gutter
  local gitsigns = { 'lewis6991/gitsigns.nvim', opts = {} }

  -- Unobtrusive scrollbar
  local satellite = { 'lewis6991/satellite.nvim', opts = {} }

  -- Toggleable minimap with <leader> m
  local minimap = {
    'isrothy/neominimap.nvim',
    lazy = false,
    keys = {
      { '<leader>m', '<cmd>Neominimap WinToggle<cr>' },
    },
    init = function()
      vim.g.neominimap = {
        auto_enable = true,
        layout = 'float',
        diagnostic = { enabled = true },
        search = { enabled = true },
        treesitter = { enabled = true },
        mark = { enabled = true },
      }
      vim.opt.wrap = false
      vim.opt.sidescrolloff = 36

      local api = require 'neominimap.api'
      vim.api.nvim_create_autocmd('VimEnter', {
        callback = function()
          pcall(api.win.disable, vim.api.nvim_get_current_win())
        end,
      })
      vim.api.nvim_create_autocmd('WinNew', {
        callback = function()
          pcall(api.win.disable, vim.api.nvim_get_current_win())
        end,
      })
    end,
  }

  -- Neovide tweaks
  if vim.g.neovide then
    vim.g.neovide_opacity = 0.80
    vim.g.neovide_window_blurred = true

    vim.g.neovide_position_animation_length = 0.03
    vim.g.neovide_scroll_animation_length = 0.15
    vim.g.neovide_cursor_animation_length = 0.03
    vim.g.neovide_cursor_smooth_blink = true
    vim.g.neovide_cursor_trail_size = 0.35
    -- vim.g.neovide_cursor_vfx_mode = 'pixiedust'
    -- vim.g.neovide_cursor_vfx_particle_lifetime = 0.5
    -- vim.g.neovide_cursor_vfx_particle_density = 0.5

    vim.g.neovide_input_macos_option_key_is_meta = 'only_left'

    vim.g.neovide_refresh_rate = 144
    vim.g.neovide_refresh_rate_idle = 10
  end

  return { theme, todos, yazi, lualine, gitsigns, satellite, minimap}
end


--------  NOTE: Plumbing -------------------------------------------------------------------------------------

-- Setup keymaps
Keymaps.Global()
Keymaps.Windowing()
Keymaps.Vim()
for filetypes, callback in pairs(Keymaps.FileType) do
  vim.api.nvim_create_autocmd('FileType', {
    pattern = filetypes,
    callback = callback,
  })
end

-- Install plugins (see :Lazy). Notes:
--   * Specifying `opts` loads the plugin with `setup(opts)`
--   * Specifying `config` just gets called on load, we're in charge of `require('...').setup(...)`
--   * Specifying `event` delays loading until that event fires
local lazy_path = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazy_path) then
  local repo = 'https://github.com/folke/lazy.nvim.git'
  local stdout = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', repo, lazy_path }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. stdout)
  end
end
vim.opt.rtp:prepend(lazy_path)

local plugins = {}
vim.list_extend(plugins, QoL())
vim.list_extend(plugins, LangSupport())
vim.list_extend(plugins, Cosmetics())
require('lazy').setup(plugins)

--[[
=====================================================================
==================== THIS CONFIG WAS INSPIRED BY ====================
=====================================================================
========                                    .-----.          ========
========         .----------------------.   | === |          ========
========         |.-""""""""""""""""""-.|   |-----|          ========
========         ||                    ||   | === |          ========
========         ||   KICKSTART.NVIM   ||   |-----|          ========
========         ||                    ||   | === |          ========
========         ||                    ||   |-----|          ========
========         ||                    ||   |:::::|          ========
========         |'-..................-'|   |____o|          ========
========         `"")----------------(""`   ___________      ========
========        /::::::::::|  |::::::::::\  \ no mouse \     ========
========       /:::========|  |==hjkl==:::\  \ required \    ========
========      '""""""""""""'  '""""""""""""'  '""""""""""'   ========
========                                                     ========
=====================================================================
=====================================================================
--]]
