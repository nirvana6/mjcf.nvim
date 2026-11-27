local dir = (arg[0] or "tests/schema_spec.lua"):match("^(.*)/") or "tests"
local H = dofile(dir .. "/harness.lua")

local PRESET_ID = "file:///preset.xsd"
local PRESET_PATTERN = "**/*.preset.xml"

vim.lsp.config("lemminx", {
  settings = {
    xml = {
      fileAssociations = {
        { pattern = PRESET_PATTERN, systemId = PRESET_ID },
      },
    },
  },
})

local mjcf = require("mjcf")
mjcf.setup({})

local function associations()
  local cfg = vim.lsp.config["lemminx"]
  return cfg.settings.xml.fileAssociations
end

local function dup_count(list)
  local seen = {}
  local dups = 0
  for _, entry in ipairs(list) do
    local key = tostring(entry.systemId) .. "\0" .. tostring(entry.pattern)
    if seen[key] then
      dups = dups + 1
    end
    seen[key] = true
  end
  return dups
end

local function find(list, pattern, system_id)
  for _, entry in ipairs(list) do
    if entry.pattern == pattern and (system_id == nil or entry.systemId == system_id) then
      return entry
    end
  end
end

local bundled = mjcf.get_config().schema_path
local list = associations()
H.check(find(list, PRESET_PATTERN, PRESET_ID) ~= nil, "preset association is kept")
H.check(find(list, "**/*.mjcf.xml", bundled) ~= nil, "default **/*.mjcf.xml is appended")
H.check(find(list, "**/*.mujoco.xml", bundled) ~= nil, "default **/*.mujoco.xml is appended")
H.eq(#list, 3, "preset plus two suffixes")
H.eq(dup_count(list), 0, "no duplicate associations after setup")
H.eq(list[1].systemId, PRESET_ID, "preset stays ahead of MJCF entries")

mjcf.setup({
  schema = { globs = { "**/extra.mjcf" } },
})
list = associations()
bundled = mjcf.get_config().schema_path
H.check(find(list, PRESET_PATTERN, PRESET_ID) ~= nil, "preset survives a second setup")
H.check(find(list, "**/*.mjcf.xml", bundled) ~= nil, "suffix pattern survives globs")
H.check(find(list, "**/extra.mjcf", bundled) ~= nil, "opts.schema.globs adds a pattern")
H.eq(dup_count(list), 0, "globs do not duplicate existing associations")

mjcf.setup({
  schema_path = "/tmp/custom-mjcf.xsd",
})
list = associations()
local override = mjcf.get_config().schema_path
H.check(find(list, "**/*.mjcf.xml", override) ~= nil, "schema_path overrides systemId")
H.check(find(list, PRESET_PATTERN, PRESET_ID) ~= nil, "override does not drop the preset")
H.eq(dup_count(list), 0, "override does not duplicate associations")

H.finish()
