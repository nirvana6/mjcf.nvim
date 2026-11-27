local M = {}

local function entry_key(entry)
  return tostring(entry.systemId) .. "\0" .. tostring(entry.pattern)
end

local function append_unique(dst, seen, entry)
  if type(entry) ~= "table" then
    return
  end
  local key = entry_key(entry)
  if seen[key] then
    return
  end
  seen[key] = true
  dst[#dst + 1] = entry
end

local function existing_associations()
  local cfg = vim.lsp.config["lemminx"]
  if type(cfg) ~= "table" or type(cfg.settings) ~= "table" then
    return {}
  end
  local xml = cfg.settings.xml
  if type(xml) ~= "table" or type(xml.fileAssociations) ~= "table" then
    return {}
  end
  return xml.fileAssociations
end

local function patterns_for(opts)
  local patterns = {}
  for _, suffix in ipairs(opts.schema.suffixes) do
    patterns[#patterns + 1] = "**/" .. suffix
  end
  for _, glob in ipairs(opts.schema.globs) do
    patterns[#patterns + 1] = glob
  end
  return patterns
end

function M.associations(opts)
  local system_id = opts.schema_path
  local merged = {}
  local seen = {}
  for _, entry in ipairs(existing_associations()) do
    append_unique(merged, seen, vim.deepcopy(entry))
  end
  for _, pattern in ipairs(patterns_for(opts)) do
    append_unique(merged, seen, { pattern = pattern, systemId = system_id })
  end
  return merged
end

function M.register(opts)
  local merged = M.associations(opts)
  vim.lsp.config("lemminx", {
    settings = {
      xml = {
        fileAssociations = merged,
      },
    },
  })
  return merged
end

return M
