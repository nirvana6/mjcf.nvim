local M = {}

local SUFFIXES = { ".mjcf.xml", ".mujoco.xml" }

function M.has_suffix(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  for _, suffix in ipairs(SUFFIXES) do
    if #name >= #suffix and name:sub(-#suffix) == suffix then
      return true
    end
  end
  return false
end

function M.line_opens_mujoco(line)
  return line:match("^%s*<mujoco[>%s/]") ~= nil or line:match("^%s*<mujoco$") ~= nil
end

--- True when the buffer should be treated as MJCF.
--- Suffixes win outright. Otherwise filetype must be `xml` or empty, and a
--- `<mujoco` root must appear in the first 200 lines.
function M.is_mjcf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if M.has_suffix(name) then
    return true
  end
  local ft = vim.bo[buf].filetype
  if ft ~= "xml" and ft ~= "" then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 200, false)
  for _, line in ipairs(lines) do
    if M.line_opens_mujoco(line) then
      return true
    end
  end
  return false
end

return M
