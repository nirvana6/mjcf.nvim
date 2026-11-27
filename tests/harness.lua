local src = debug.getinfo(1, "S").source:gsub("^@", "")
local tests_dir = vim.fn.fnamemodify(src, ":p:h")
local root = vim.fn.fnamemodify(tests_dir, ":h")

vim.opt.rtp:prepend(root)
vim.o.more = false

local M = {
  pass = 0,
  fail = 0,
  root = root,
}

function M.check(cond, name)
  if cond then
    M.pass = M.pass + 1
    print("ok " .. name)
  else
    M.fail = M.fail + 1
    print("FAIL " .. name)
  end
end

function M.eq(actual, expected, name)
  if actual == expected then
    M.check(true, name)
  else
    M.check(
      false,
      string.format("%s (got %s, expected %s)", name, tostring(actual), tostring(expected))
    )
  end
end

function M.contains(hay, needle, name)
  if type(hay) == "string" and hay:find(needle, 1, true) then
    M.check(true, name)
  else
    M.check(false, string.format("%s (missing %q in %s)", name, needle, tostring(hay)))
  end
end

function M.read(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

function M.finish()
  print(string.format("RESULT %d %d", M.pass, M.fail))
  io.stdout:flush()
  if M.fail > 0 then
    vim.cmd("cquit 1")
  end
end

return M
