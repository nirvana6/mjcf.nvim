local M = {}

local LINE_PATTERNS = {
  "%f[%a][Ll]ine%s+[Nn]umber%s*=%s*(%d+)",
  "%f[%a][Ll]ine%s+(%d+)",
}

local function last_plain(text, needle)
  local last
  local from = 1
  while from <= #text do
    local found = text:find(needle, from, true)
    if not found then
      break
    end
    last = found
    from = found + 1
  end
  return last
end

local function last_line_token(text)
  local best
  for _, pat in ipairs(LINE_PATTERNS) do
    local from = 1
    while from <= #text do
      local s, e, num = text:find(pat, from)
      if not s then
        break
      end
      if not best or s > best.s or (s == best.s and e > best.e) then
        best = { s = s, e = e, n = tonumber(num) }
      end
      from = e + 1
    end
  end
  return best
end

local function collapse(text)
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = text:gsub("[ \t]+", " ")
  text = text:gsub("\n+", " ")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub(",%s*$", "")
  text = text:gsub("%s+$", "")
  return text
end

local function file_line_count(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local n = 0
  for _ in f:lines() do
    n = n + 1
  end
  f:close()
  if n < 1 then
    return 1
  end
  return n
end

local function same_file(mentioned, file_path)
  if type(file_path) ~= "string" or file_path == "" then
    return false
  end
  if mentioned == file_path then
    return true
  end
  local base = file_path:match("([^/\\]+)$")
  if mentioned == base then
    return true
  end
  if #mentioned > 0 and file_path:sub(-#mentioned) == mentioned then
    local prev = file_path:sub(-#mentioned - 1, -#mentioned - 1)
    if prev == "/" or prev == "\\" or prev == "" then
      return true
    end
  end
  return false
end

local function looks_like_file(name)
  if name == "" or name:find("%s") then
    return false
  end
  if name:find("^<.*>$") then
    return false
  end
  if name:find("[/\\]") then
    return true
  end
  return name:match("%.[A-Za-z][%w]*$") ~= nil
end

local function foreign_filename(text, file_path)
  for quoted in text:gmatch("['\"]([^'\"]+)['\"]") do
    if looks_like_file(quoted) and not same_file(quoted, file_path) then
      return quoted
    end
  end
  return nil
end

--- Parse MuJoCo compiler stderr into Neovim diagnostics.
--- Line numbers in the returned items are 0-based (`lnum`).
--- The MuJoCo line is the last `line <n>` / `Line number=<n>` token.
---@param stderr_text string
---@param file_path string
---@return vim.Diagnostic[]
function M.parse(stderr_text, file_path)
  if type(stderr_text) ~= "string" or stderr_text == "" then
    return {}
  end

  local token = last_line_token(stderr_text)
  local line = token and token.n or 1
  if not line or line < 1 then
    line = 1
  end

  local msg_start = 1
  local err_at = last_plain(stderr_text, "Error: ")
  if err_at then
    msg_start = err_at + #"Error: "
  else
    local value_at = last_plain(stderr_text, "ValueError:")
    if value_at then
      msg_start = value_at + #"ValueError:"
    end
  end

  local msg_end = #stderr_text
  if token and token.s >= msg_start then
    msg_end = token.s - 1
  end

  local message = collapse(stderr_text:sub(msg_start, msg_end))
  if message == "" then
    message = "compile error"
  end

  local foreign = foreign_filename(stderr_text:sub(msg_start), file_path)
  if foreign and message:sub(1, #foreign) ~= foreign then
    message = foreign .. ": " .. message
  end

  local total = file_line_count(file_path)
  if total and line > total then
    line = total
  end

  return {
    {
      lnum = line - 1,
      col = 0,
      message = message,
      severity = vim.diagnostic.severity.ERROR,
      source = "mjcf",
    },
  }
end

return M
