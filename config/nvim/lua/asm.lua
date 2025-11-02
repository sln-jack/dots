-- ASM ANALYSIS EXPERIMENTS --------------------------------------------------------------------------------------
-- This is experimental code for advanced assembly analysis and visualization
-- Eventually the framework should make this kind of custom tooling super easy to build!

_G.asm = {
  files = {},   -- id -> path
  locs = {},    -- line -> {file, line, col}
  funcs = {},   -- {name, start, stop}
  branches = {},-- {line, target}
  labels = {},  -- label -> line
}

-- Analysis pass: gather files, locs, funcs, branches
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

-- Inline source preview for `.loc`
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

-- Function guides
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

-- Branch arrows
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

-- Simple orchestrator
function _G.asm_refresh()
  asm_analyze()
  asm_function_guides()
  asm_branch_arrows()
  asm_inline_src()
end

--[[
FRAMEWORK IDEAS FROM THIS EXPERIMENT:
1. Easy namespace management for virtual text overlays
2. Buffer analysis passes that build up structured data
3. Visual guides and arrows connecting related code
4. Inline previews from other files
5. Project-specific visualization tools

The framework should make it trivial to:
- Parse buffer content into structured data
- Create visual overlays with extmarks
- Connect related pieces of code visually
- Show context from other files inline
- Toggle different visualization modes
]]