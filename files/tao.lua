local F = require('framework')

F.lsp.config.csharp.solution = function()
  return F.project.root() .. '/rider/JustScriptGen/JustScriptGen.sln'
end

F.setup {
  keys = {
    binds = {},
  },
}
