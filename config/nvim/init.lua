local F = require('framework')

--[[

# TODO
-  Ripgrep word in buffer/project
-  Copy github branch/permalink to selected line / range
-  Clangd toggleable inlay hints for fn args
-  fix C-v p yiw`
-  Focus active file and collapse all others when toggling tree 
-  Setup OSC52 escape sequences <https://jvns.ca/til/vim-osc52/>
-  `mksh path/to/scriptname`
-  Try remote-ssh.nvim <https://neovimcraft.com/plugin/inhesrom/remote-ssh.nvim/>
-  Setup C# LSP
-  Setup neogit + diffview
-  `:help nvim-treesitter-incremental-selection-mod`
-  https://github.com/nvim-treesitter/nvim-treesitter-textobjects
-  https://github.com/davidmh/cmp-nerdfonts/blob/main/lua/cmp_nerdfonts/source.lua

--]]

F.setup {
  keys = {
    -------- Files -------------------------------------------------------------------------------------------

    [{'Find file (root)', '<leader>f'}] = F.pick.file.with({ dir = F.project.root }),
    [{'Find file (proj)', '<leader>F'}] = F.pick.file.with({ dir = F.project.nearest }),

    [{ 'Prev buffer', '<leader><tab>' }]   = F.edit.with('#'),
    [{ 'Pick buffer', '<leader><S-tab>' }] = F.pick.buffer,

    -------- Grep --------------------------------------------------------------------------------------------

    [{ 'Grep (project)', {'n','v'}, '<leader>/' }] = F.grep.with({ dir = F.project.root }),
    [{ 'Grep (cwd)',     {'n','v'}, '<leader>.' }] = F.grep.with({ dir = F.cwd }),
    [{ 'Grep (buffer)',  {'n','v'}, '<leader>,' }] = F.grep,

    [{ 'Grep hidden (project)', {'n','v'}, '<leader>?' }] = F.grep.with({ hidden = true, gitignored = true, dir = F.project.root }),
    [{ 'Grep hidden (cwd)',     {'n','v'}, '<leader>>' }] = F.grep.with({ hidden = true, gitignored = true, dir = F.cwd}),
    [{ 'Grep hidden (buffer)',  {'n','v'}, '<leader><' }] = F.grep.with({ hidden = true, gitignored = true }),

    -------- LSP ---------------------------------------------------------------------------------------------

    [{ 'LSP rename', '<leader>r' }] = F.lsp.rename,
    [{ 'LSP definition', '<leader>d' }] = F.lsp.definition,
    [{ 'LSP implementations', '<leader>D' }] = F.lsp.implementations,
    [{ 'LSP symbols', '<leader>ls' }] = F.lsp.symbols,
    [{ 'LSP action', '<leader>a' }] = F.lsp.action,
    [{ 'LSP references', '<leader>lr' }] = F.lsp.references,
    [{ 'LSP doc symbols', '<leader>ld' }] = F.lsp.doc_symbols,
    [{ 'LSP types', '<leader>lt' }] = F.lsp.types,
    [{ 'LSP format', '<leader>lf' }] = F.lsp.format,
    [{ 'Next diagnostic', '<leader>w' }] = F.lsp.next_diagnostic.with({ 'ERROR', 'WARN', 'INFO', 'HINT' }),
    [{ 'Next warning', '<leader>W' }] = F.lsp.next_diagnostic.with({ 'WARN' }),

    -- Search
    [{ 'Resume search', '<leader>sr' }] = function() require('telescope.builtin').resume() end,
    [{ 'Search help', '<leader>sh' }] = function() require('telescope.builtin').help_tags() end,
    [{ 'Search keymaps', '<leader>sk' }] = function() require('telescope.builtin').keymaps() end,
    [{ 'Search telescope', '<leader>st' }] = function() require('telescope.builtin').builtin() end,
    [{ 'Search diagnostics', '<leader>sq' }] = function() require('telescope.builtin').diagnostics() end,

    -- Project
    [{ 'Edit init.lua', '<leader>pc' }] = F.edit.with(vim.fn.stdpath('config') .. '/init.lua'),
    [{ 'Edit project init.lua', '<leader>pC' }] = function()
      local project = F.project.root()
      if project then
        vim.fn.mkdir(project .. '/.nvim')
        F.edit(project .. '/.nvim/init.lua')
      end
    end,

    [{ 'Pick project', '<leader>pp' }] = F.pick.dir.with({ dir = '~/code', depth = 1 }),
    [{ 'Edit dotfiles', '<leader>pd' }] = F.pick.file.with({ dir = '~/code/dots' }),
    [{ 'Edit TODO.md', '<leader>pt' }] = F.edit.with('~/notes/TODO.md'),

    -------- Window ------------------------------------------------------------------------------------------

    [{':w',  {'i', 'n'}, '<D-s>'}]   = F.cmd.with(':w'),
    [{':q',  {'i', 'n'}, '<M-q>'}]   = F.cmd.with(':q'),
    [{':wq', {'i', 'n'}, '<M-S-q>'}] = F.cmd.with(':wq'),

    [{'Split horiz',  '<M-->'}] = F.cmd.with(':split'),
    [{'Split vert',   '<M-=>'}] = F.cmd.with(':vsplit'),

    [{'Focus left',  '<M-h>'}] = F.cmd.with(':wincmd h'),
    [{'Focus right', '<M-l>'}] = F.cmd.with(':wincmd l'),
    [{'Focus down',  '<M-j>'}] = F.cmd.with(':wincmd j'),
    [{'Focus up',    '<M-k>'}] = F.cmd.with(':wincmd k'),

    [{'Move left',  '<M-S-h>'}] = F.cmd.with(':wincmd H'),
    [{'Move right', '<M-S-l>'}] = F.cmd.with(':wincmd L'),
    [{'Move down',  '<M-S-j>'}] = F.cmd.with(':wincmd J'),
    [{'Move up',    '<M-S-k>'}] = F.cmd.with(':wincmd K'),

    [{'Resize left',  '<M-a>'}] = function() require('smart-splits').resize_left() end,
    [{'Resize down',  '<M-s>'}] = function() require('smart-splits').resize_down() end,
    [{'Resize up',    '<M-w>'}] = function() require('smart-splits').resize_up() end,
    [{'Resize right', '<M-d>'}] = function() require('smart-splits').resize_right() end,

    -------- Edits --------------------------------------------------------------------------------------------

    [{'Remove extra whitespace', '<leader>ew'}] = F.cmd.with('%s/\\s\\+$//e'),

    -------- Misc --------------------------------------------------------------------------------------------

    [{ 'Clear search', '<Esc>' }] = F.cmd.with(':nohlsearch'),

    [{ 'Yazi', '<leader>y' }] = F.cmd.with(':Yazi'),
    [{ 'Toggle tree', '<leader>t' }] = F.tree.toggle,
    [{ 'Re-yank selection after paste', { 'x' }, 'p' }] = function()
      vim.cmd.normal('pgvy', true)
    end,
    [{ 'Line start', { 'i' }, '<C-a>' }] = '<C-o>0',
    [{ 'Line end', { 'i' }, '<C-e>' }] = '<C-o>$',
    [{ 'Delete to EOL', { 'i' }, '<C-k>' }] = '<C-o>D',

    -- Neovide zoom
    [{ 'Zoom in', { 'n','i' }, '<D-=>'}] = function()
      if vim.g.neovide then vim.g.neovide_scale_factor = (vim.g.neovide_scale_factor or 1.0) + 0.1 end
    end,
    [{ 'Zoom out', { 'n','i' }, '<D-->'}] = function()
      if vim.g.neovide then vim.g.neovide_scale_factor = (vim.g.neovide_scale_factor or 1.0) - 0.1 end
    end,
    [{ 'Zoom reset', { 'n','i' }, '<D-+>'}] = function()
      if vim.g.neovide then vim.g.neovide_scale_factor = 1.0 end
    end,

    -- Project markers
    [{ 'Project: mark here', '<leader>pm' }] = F.project.mark,

    -- Filetype specific
    [{ 'Quit help/man/qf', 'q' }] = F.when({lang = {'help', 'man', 'qf', 'lspinfo'}}, F.cmd.with(':q')),
  },
}
