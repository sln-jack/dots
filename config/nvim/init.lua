local F = require('framework')

--[[

# TODO
- [x] Ripgrep word in buffer/project
- [x] Setup OSC52 escape sequences <https://jvns.ca/til/vim-osc52/>
- [x] fix C-v p yiw`
- [x] Remap lang keys
- [x] K docs replacement and C-jk to scroll
- [x] Clangd toggleable inlay hints for fn args
- [x] Copy github branch/permalink to selected line / range
- [x] fish `mksh path/to/scriptname`
- [x] https://github.com/nvim-treesitter/nvim-treesitter-textobjects
- [x] Patch treesitter-textobjects to get @block.inner/outer working for c/cpp/c#
- [x] Telescope live grep args
- [~] Setup neogit + diffview
- [ ] Setup C# LSP
- [ ] Focus active file and collapse all others when toggling tree 
- [ ] `:help nvim-treesitter-incremental-selection-mod`
- [ ] Try remote-ssh.nvim <https://neovimcraft.com/plugin/inhesrom/remote-ssh.nvim/>
- [ ] https://github.com/davidmh/cmp-nerdfonts/blob/main/lua/cmp_nerdfonts/source.lua

--]]

F.setup {
  keys = {
    aliases = {
      ['<main>'] = '<space>',
      ['<lang>'] = '\\',
      ['<proj>']  = '<f6>',
      ['<ctx>'] = '<f7>',
      ['<misc>'] = '<f8>',
    },
    binds = {
      [{'Git status', '<main>gs'}] = F.git.ui,
      [{'Git log',    '<main>gl'}] = F.git.ui.with({'log'}),
      [{'Git diff',   '<main>gd'}] = F.git.ui.with({'diff'}),

      -------- Files -------------------------------------------------------------------------------------------

      [{'Find file (root)', '<main>f'}] = F.pick.file.with({ dir = F.project.root }),
      [{'Find file (proj)', '<main>F'}] = F.pick.file.with({ dir = F.project.nearest }),

      [{'Prev buffer', '<main><tab>'}] = F.edit.with('#'),
      [{'Pick buffer', '<main>`'}]     = F.pick.buffer,

      [{'Notifs', '<main>n'}] = F.pick.notification,

      -------- Grep --------------------------------------------------------------------------------------------

      [{ 'Grep (project)', {'n','v'}, '<main>/' }] = F.grep.with({ dir = F.project.root }),
      [{ 'Grep (cwd)',     {'n','v'}, '<main>.' }] = F.grep.with({ dir = F.cwd }),
      [{ 'Grep (buffer)',  {'n','v'}, '<main>,' }] = F.grep,

      [{ 'Grep hidden (project)', {'n','v'}, '<main>?' }] = F.grep.with({ hidden = true, gitignored = true, dir = F.project.root }),
      [{ 'Grep hidden (cwd)',     {'n','v'}, '<main>>' }] = F.grep.with({ hidden = true, gitignored = true, dir = F.cwd}),
      [{ 'Grep hidden (buffer)',  {'n','v'}, '<main><' }] = F.grep.with({ hidden = true, gitignored = true }),

      -------- LSP ---------------------------------------------------------------------------------------------

      [{'Rename', '<lang><lang>'}] = F.lsp.rename,
      [{'Hover',  '<lang><tab>'}]  = F.when({lang = {'c', 'cpp'}}, F.cmd.with(':LspClangdSwitchSourceHeader')),
      [{'Action', '<lang>a'}]      = F.lsp.action,
      [{'Hints',  '<lang>h'}]      = F.lsp.toggle_hints,

      [{'Goto def',     '<lang>d'}] = F.lsp.definition,
      [{'Goto impl',    '<lang>D'}] = F.lsp.impls,
      [{'Goto typedef', '<lang>t'}] = F.lsp.typedefs,
      [{'Find refs',    '<lang>r'}] = F.lsp.references,
      [{'Find symbol',  '<lang>s'}] = F.lsp.symbols,

      [{'Next error', '<lang>e'}] = F.lsp.next_diagnostic.with({'ERROR', 'WARN', 'INFO', 'HINT'}),
      [{'Next warn',  '<lang>w'}] = F.lsp.next_diagnostic.with({'WARN'}),
      [{'Format',     '<lang>f'}] = F.lsp.format,

      [{'Permalink',      {'n','v'}, '<lang>l'}] = F.git.permalink,
      [{'Permalink main', {'n','v'}, '<lang>L'}] = F.git.permalink.with({ branch = 'main' }),

      -------- DAP ---------------------------------------------------------------------------------------------

      [{'Start',  '<ctx>d'}] = F.dap.start,
      [{'Detach', '<ctx>q'}] = F.dap.disconnect,
      [{'Stop',   '<ctx>Q'}] = F.dap.stop,
      [{'REPL',   '<ctx>r'}] = F.dap.repl,

      [{'Continue',           '<ctx>c'}] = F.dap.continue,
      [{'Continue to cursor', '<ctx>C'}] = F.dap.continue_to_cursor,

      [{'Step over', '<ctx>n'}] = F.dap.step_over,
      [{'Step into', '<ctx>i'}] = F.dap.step_in,
      [{'Step out',  '<ctx>o'}] = F.dap.step_out,

      [{'Breakpoint',               '<ctx>b'}] = F.dap.breakpoint,
      [{'Breakpoint (conditional)', '<ctx>B'}] = F.dap.breakpoint_condition,

      -------- Search ------------------------------------------------------------------------------------------

      [{'Resume search',      '<main>sr'}] = function() require('telescope.builtin').resume() end,
      [{'Search help',        '<main>sh'}] = function() require('telescope.builtin').help_tags() end,
      [{'Search keymaps',     '<main>sk'}] = function() require('telescope.builtin').keymaps() end,
      [{'Search telescope',   '<main>st'}] = function() require('telescope.builtin').builtin() end,
      [{'Search diagnostics', '<main>sq'}] = function() require('telescope.builtin').diagnostics() end,

      -------- Project -----------------------------------------------------------------------------------------

      [{ 'Edit init.lua', '<main>pc' }] = F.edit.with(vim.fn.stdpath('config') .. '/init.lua'),
      [{ 'Edit project init.lua', '<main>pC' }] = function()
        local project = F.project.root()
        if project then
          vim.fn.mkdir(project .. '/.nvim')
          F.edit(project .. '/.nvim/init.lua')
        end
      end,

      [{ 'Pick project', '<main>pp' }] = F.pick.dir.with({ dir = '~/code', depth = 1 }),
      [{ 'Edit dotfiles', '<main>pd' }] = F.pick.file.with({ dir = '~/code/dots' }),
      [{ 'Edit TODO.md', '<main>pt' }] = F.edit.with('~/notes/TODO.md'),

      -------- Window ------------------------------------------------------------------------------------------

      [{':w',  {'i', 'n'}, '<D-s>'}]   = F.cmd.with(':w'),
      [{':q',  {'i', 'n'}, '<M-q>'}]   = F.cmd.with(':q'),
      [{':wq', {'i', 'n'}, '<M-S-q>'}] = F.cmd.with(':wq'),

      [{'Split horiz',  '<M-->'}] = F.cmd.with(':split'),
      [{'Split vert',   '<M-=>'}] = F.cmd.with(':vsplit'),

      [{'Focus left',  '<M-h>'}] = F.cmd.with(':TmuxNavigateLeft'),
      [{'Focus down',  '<M-j>'}] = F.cmd.with(':TmuxNavigateDown'),
      [{'Focus up',    '<M-k>'}] = F.cmd.with(':TmuxNavigateUp'),
      [{'Focus right', '<M-l>'}] = F.cmd.with(':TmuxNavigateRight'),

      [{'Move left',  '<M-S-h>'}] = F.cmd.with(':wincmd H'),
      [{'Move down',  '<M-S-j>'}] = F.cmd.with(':wincmd J'),
      [{'Move up',    '<M-S-k>'}] = F.cmd.with(':wincmd K'),
      [{'Move right', '<M-S-l>'}] = F.cmd.with(':wincmd L'),

      [{'Resize left',  '<M-a>'}] = function() require('smart-splits').resize_left() end,
      [{'Resize down',  '<M-s>'}] = function() require('smart-splits').resize_down() end,
      [{'Resize up',    '<M-w>'}] = function() require('smart-splits').resize_up() end,
      [{'Resize right', '<M-d>'}] = function() require('smart-splits').resize_right() end,

      -------- Edits --------------------------------------------------------------------------------------------

      [{'Remove extra whitespace', '<main>ew'}] = F.cmd.with('%s/\\s\\+$//e'),

      -------- Misc --------------------------------------------------------------------------------------------

      [{ 'Clear search', '<Esc>' }] = F.cmd.with(':nohlsearch'),

      [{ 'Yazi', '<main>y' }] = F.cmd.with(':Yazi'),
      [{ 'Toggle tree', '<main>t' }] = F.tree.toggle,
      [{ 'Re-yank selection after paste', { 'x' }, 'p' }] = F.cmd.with('normal! pgvy'),
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
      [{ 'Project: mark here', '<main>pm' }] = F.project.mark,

      -- Filetype specific
      [{ 'Quit help/man/qf', 'q' }] = F.when({lang = {'help', 'man', 'qf', 'lspinfo'}}, F.cmd.with(':q')),
    },
  }
}
