
-- Register OSC 52 as the clipboard provider so the +/* registers reach the
-- host: the container is headless (no display/pbcopy) and nvim only auto-enables
-- OSC 52 under SSH, not docker run. Whether plain yanks route here stays under
-- the existing opt.clipboard switch ("" = local only, "unnamedplus" = to host).
local osc52 = require("vim.ui.clipboard.osc52")
-- Paste reads the unnamed register so it never blocks waiting on an OSC 52 read
-- response (many terminals don't answer); copy still reaches the host clipboard.
local function paste()
  return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end
vim.g.clipboard = {
  name = "OSC 52",
  copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
  paste = { ["+"] = paste, ["*"] = paste },
}
