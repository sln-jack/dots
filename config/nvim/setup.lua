-- PLUGINS AND VIM SETUP -----------------------------------------------------------------------------------------
-- This file contains plugin setup and vim configuration that rarely changes
-- Lazy.nvim doesn't support re-eval, so this is only loaded once on startup

local M = {}

-- LAZY.NVIM BOOTSTRAP -------------------------------------------------------------------------------------------

local lazy_path = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazy_path) then
  local repo = 'https://github.com/folke/lazy.nvim.git'
  vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', repo, lazy_path }
end
vim.opt.rtp:prepend(lazy_path)

-- PLUGIN DEFINITIONS --------------------------------------------------------------------------------------------

local plugins = {
  -- Theme
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    opts = {
      on_colors = function(colors)
        colors.border = colors.white
      end,
    },
    init = function() vim.cmd.colorscheme 'tokyonight-night' end,
  },

  -- Telescope
  {
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-telescope/telescope-live-grep-args.nvim' },
      { 'rcarriga/nvim-notify' },
      { 'nvim-tree/nvim-web-devicons', enabled = true },
    },
    config = function()
      local telescope = require('telescope')
      local livegrep = require('telescope-live-grep-args.actions')
      telescope.load_extension('fzf')
      telescope.load_extension('ui-select')
      telescope.load_extension('live_grep_args')
      telescope.load_extension('notify')


      telescope.setup {
        defaults = {
          sorting_strategy = 'ascending',
          layout_config = { prompt_position = 'top' },
          mappings = {
            i = {
              ['<Esc>'] = 'close',
              ['<C-j>'] = 'move_selection_next',
              ['<C-k>'] = 'move_selection_previous',
            },
          },
        },
        pickers = {
          find_files = { follow = true },
        },
      }
    end,
  },

  -- Treesitter
  {
    'nvim-treesitter/nvim-treesitter',
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-context', opts = {} },
      { 'foltik/nvim-treesitter-textobjects' },
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
            ['af'] = '@function.outer',
            ['if'] = '@function.inner',

            ['as'] = '@class.outer',
            ['is'] = '@class.inner',

            ['ab'] = '@block.outer',
            ['ib'] = '@block.inner',

            ['ac'] = '@call.outer',
            ['ic'] = '@call.inner',

            ['ap'] = '@parameter.outer',
            ['ip'] = '@parameter.inner',

            ['al'] = '@assignment.lhs',
            ['il'] = '@assignment.lhs',

            ['ar'] = '@assignment.rhs',
            ['ir'] = '@assignment.rhs',
          },
          selection_modes = {
            ['@function.inner'] = 'V',
            ['@function.outer'] = 'V',
            ['@block.inner'] = 'V',
            ['@block.outer'] = 'V',
            ['@class.inner'] = 'V',
            ['@class.outer'] = 'V',
          },
        },
        move = {
          enable = true,
          set_jumps = true,
          goto_next_start = {
            [']f'] = '@function.outer',
            [']s'] = '@class.outer',
            [']b'] = '@block.inner',
          },
          goto_previous_start = {
            ['[f'] = '@function.outer',
            ['[s'] = '@class.outer',
            ['[b'] = '@block.inner',
          },
        },
        swap = {
          enable = true,
          swap_next = {
            ['\\]'] = '@parameter.inner',
          },
          swap_previous = {
            ['\\['] = '@parameter.inner',
          },
        },
        lsp_interop = {
          enable = true,
          border = 'none',
          floating_preview_opts = {},
          peek_definition_code = {
            ["\\p"] = "@class.outer",
          },
        },
      },
    },
  },

  -- LSP
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'j-hui/fidget.nvim', opts = {} },
      'saghen/blink.cmp',
      { 'saecki/live-rename.nvim', opts = { keys = { cancel = { { 'i', '<Esc>' } } } } },
    },
    config = function()
      vim.lsp.config('*', {
        capabilities = require('blink.cmp').get_lsp_capabilities(),
      })

      vim.lsp.enable('clangd')

      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
              path = { 'lua/?.lua', 'lua/?/init.lua' },
            },
            workspace = {
              checkThirdParty = false,
              library = { vim.env.VIMRUNTIME, '${3rd}/luv/library' }
            }
          }
        }
      })
      vim.lsp.enable('lua_ls')

      -- LSP attach hooks
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          local bufnr = event.buf
          local name = vim.api.nvim_buf_get_name(bufnr)
          local supports = function(method)
            return client and client.supports_method(method, { bufnr = event.buf })
          end

          local is_fake_file = name:match('^%w%a+://') ~= nil  -- diff://, git:// etc.
          if is_fake_file then
            return
          end

          -- Toggle inlay hints
          if supports(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            vim.keymap.set('n', '<leader>li', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled(event.buf), { bufnr = event.buf })
            end, { buffer = event.buf })
          end

          -- Highlight references under cursor
          if supports(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local group = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              group = group, buffer = event.buf, callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              group = group, buffer = event.buf, callback = vim.lsp.buf.clear_references,
            })
          end
        end,
      })
    end,
  },

  -- Autocomplete
  {
    'saghen/blink.cmp',
    event = 'VimEnter',
    build = 'cargo build --release',
    opts = {
      signature = { enabled = true },
      fuzzy = { implementation = 'prefer_rust_with_warning' },
      sources = { default = { 'lsp', 'path' } },
      keymap = {
        preset = 'none',
        ['<tab>'] = { 'accept', 'fallback' },
        ['<Up>'] = { 'select_prev', 'fallback' },
        ['<Down>'] = { 'select_next', 'fallback' },
        ['<C-space>'] = { 'show' },
        ['<C-d>'] = { 'show_documentation' },
        ['<C-s>'] = { 'show_signature' },
        ['<C-j>'] = { 'scroll_documentation_down', 'scroll_signature_down', 'fallback' },
        ['<C-k>'] = { 'scroll_documentation_up',   'scroll_signature_up',   'fallback' },
      },
    },
  },

  -- Formatting
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        local ty = vim.bo[bufnr].filetype
        if ty == 'rust' then
          return { timeout_ms = 500, lsp_format = 'fallback' }
        end
        return nil
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        rust = { 'rustfmt' },
      },
    },
  },

  -- Mini modules
  {
    'echasnovski/mini.nvim',
    config = function()
      require('mini.ai').setup { n_lines = 500 }
      require('mini.surround').setup { n_lines = 500 }
      require('mini.comment').setup {}
      require('mini.splitjoin').setup {}
      require('mini.align').setup {}
      require('mini.move').setup {
        mappings = {
          left = '<M-Left>', right = '<M-Right>', down = '<M-Down>', up = '<M-Up>',
          line_left = '<M-Left>', line_right = '<M-Right>', line_down = '<M-Down>', line_up = '<M-Up>',
        },
      }
      require('mini.operators').setup {}
    end,
  },

  -- Additional tools
  { 'mrjones2014/smart-splits.nvim', opts = {} },
  { 'NMAC427/guess-indent.nvim', opts = {} },
  { 'NotAShelf/direnv.nvim', opts = { autoload_direnv = true } },

  -- Git
  { 'lewis6991/gitsigns.nvim', opts = {} },
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    opts = {}
  },

  -- UI
  { 'nvim-lualine/lualine.nvim', opts = { 
    options = { component_separators = '', section_separators = '' },
    sections = {
      lualine_a = { 'filename' }, lualine_b = { 'branch', 'diff', 'diagnostics' }, lualine_c = {},
      lualine_x = {}, lualine_y = { 'progress' }, lualine_z = { 'location' },
    },
    inactive_sections = {
      lualine_a = {}, lualine_b = {}, lualine_c = { 'filename' },
      lualine_x = { 'location' }, lualine_y = {}, lualine_z = {},
    },
  }},
  { 'folke/which-key.nvim', event = 'VimEnter', opts = { delay = 500, icons = { mappings = true } } },
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = 'nvim-lua/plenary.nvim', opts = { signs = false } },
  { 'nvim-tree/nvim-tree.lua', opts = { 
    disable_netrw = false,
    hijack_netrw = false,
    filters = { dotfiles = true },
  } },
  { 'mikavilpas/yazi.nvim', event = 'VeryLazy', dependencies = { 'nvim-lua/plenary.nvim' }, opts = {} },
  { 'lewis6991/satellite.nvim', opts = {} },
  {
    'rcarriga/nvim-notify',
    event = 'VeryLazy',
    config = function()
      local notify = require('notify')
      notify.setup {
        render = 'wrapped-compact',
        stages = 'slide',
        timeout = 2000,
        background_colour = 'None',
      }
      vim.notify = notify
    end,
  },
  { 'isrothy/neominimap.nvim', lazy = false, keys = { { '<leader>m', '<cmd>Neominimap WinToggle<cr>' } },
    init = function()
      vim.g.neominimap = {
        auto_enable = true, layout = 'float', diagnostic = { enabled = true },
        search = { enabled = true }, treesitter = { enabled = true }, mark = { enabled = true },
      }
      vim.opt.wrap = false
      vim.opt.sidescrolloff = 36
      local api = require 'neominimap.api'
      vim.api.nvim_create_autocmd('VimEnter', { callback = function() pcall(api.win.disable, vim.api.nvim_get_current_win()) end })
      vim.api.nvim_create_autocmd('WinNew', { callback = function() pcall(api.win.disable, vim.api.nvim_get_current_win()) end })
    end,
  },
}

-- VIM OPTIONS ---------------------------------------------------------------------------------------------------

M.setup_vim = function()
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  -- Behavior
  vim.o.mouse = 'a'                   -- Enable mouse input
  vim.o.undofile = true                -- Save undo history
  vim.o.ignorecase = true              -- Case-insensitive search unless...
  vim.o.smartcase = true               -- ...query includes capital letters
  vim.o.inccommand = 'split'           -- Live preview of substitutions
  vim.o.breakindent = true             -- Preserve indentation on wrapped lines
  vim.o.confirm = true                 -- Ask to save instead of failing on :q
  vim.o.updatetime = 250               -- Faster LSP diagnostics
  vim.o.timeoutlen = 300               -- Decrease mapped sequence wait time

  -- Display
  vim.o.number = true                  -- Show line numbers
  vim.o.cursorline = true              -- Highlight line the cursor is on
  vim.o.scrolloff = 10                 -- Lines to keep above/below cursor
  vim.o.signcolumn = 'yes'             -- Keep left gutter always visible
  vim.o.list = true                    -- Show certain whitespace characters
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
  vim.o.laststatus = 3                 -- Display border below statusline for better visibility
  vim.o.showmode = false               -- Don't show mode (already in statusline)
  vim.o.splitbelow = true              -- Splits open down and right
  vim.o.splitright = true
  vim.opt.title = true                 -- Display cwd in window title
  vim.opt.titlestring = vim.fs.basename(vim.fn.getcwd())

  -- Cursor style and behavior
  vim.opt.guicursor = { 
    'n-v-c:block',                     -- Normal/visual/command: block cursor
    'i-ci-ve:ver25',                   -- Insert/command-insert/visual-exclude: thin vertical bar
    'r-cr:hor20',                      -- Replace/command-replace: horizontal bar
    'o:hor50',                         -- Operator-pending: thicker horizontal bar
    'a:blinkwait500-blinkoff250-blinkon250'  -- All modes: blink after 500ms inactivity
  }

  -- Relative line numbers in normal mode, absolute in insert mode
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

  -- Indentation
  vim.o.shiftwidth = 4                 -- Default indent size
  vim.o.tabstop = 4                    -- Tab width
  vim.o.expandtab = true               -- Use spaces instead of tabs

  -- Clipboard (schedule to avoid startup delay)
  vim.schedule(function()
    if vim.env.SSH_TTY then
      -- TODO: This doesn't work becuase MacOS <16 UNCONDITIONALLY
      -- POPS A DIALOG BOX ON EVERY PASTE WITH NO WAY TO DISABLE IT
      -- -- In SSH, force osc52
      -- vim.g.clipboard = 'osc52'
    else
      -- Otherwise, let vim autodetect (xclip, pbcopy, etc)
    end
    vim.o.clipboard = 'unnamedplus'
  end)

  -- Highlight on yank
  vim.api.nvim_create_autocmd('TextYankPost', {
    callback = function() vim.hl.on_yank() end,
  })

  -- Restore cursor position when reopening files (mark ")
  vim.api.nvim_create_autocmd('BufReadPost', {
    callback = function()
      if vim.tbl_contains({ 'gitcommit', 'gitrebase', 'help' }, vim.bo.filetype) then
        return
      end
      vim.cmd 'silent! normal! g`"zz'
    end,
  })

  -- Diagnostic configuration
  vim.diagnostic.config({
    float = {
      close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
    },
    severity_sort = true,              -- Sort diagnostics by severity
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = '',
        [vim.diagnostic.severity.WARN] = '',
        [vim.diagnostic.severity.INFO] = '',
      }
    }
  })

  -- Generate nice visual divider comment
  vim.api.nvim_create_user_command('Divider', function(opts)
    local comment = vim.bo.commentstring or '//'
    comment = comment:match '^[^%s]+' or comment
    local title = ' ' .. opts.args .. ' '
    local pre_pad = 6
    local post_pad = 110 - pre_pad - #title - #comment
    local divider = comment .. string.rep('-', pre_pad) .. title .. string.rep('-', post_pad)
    vim.api.nvim_put({ divider }, 'l', true, true)
  end, { nargs = 1 })

  -- Neovide tweaks
  if vim.g.neovide then
    vim.g.neovide_opacity = 0.80
    vim.g.neovide_window_blurred = true
    vim.g.neovide_position_animation_length = 0.03
    vim.g.neovide_scroll_animation_length = 0.15
    vim.g.neovide_cursor_animation_length = 0.03
    vim.g.neovide_cursor_smooth_blink = true
    vim.g.neovide_cursor_trail_size = 0.35
    vim.g.neovide_input_macos_option_key_is_meta = 'only_left'
    vim.g.neovide_refresh_rate = 144
    vim.g.neovide_refresh_rate_idle = 10
  end
end

-- MAIN SETUP ----------------------------------------------------------------------------------------------------

M.setup = function()
  M.setup_vim()
  require('lazy').setup(plugins)
end

return M
