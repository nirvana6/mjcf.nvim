local M = {}

M.EXPECTED_SHA256 = "82357103334ca30489210c9d56dc09e52bb668d97b94d391963a39632323c27f"
M.SCHEMA_NAME = "mjcf-4.0.1.xsd"

local defaults = {
  schema_path = nil,
  schema = {
    enabled = true,
    globs = {},
    suffixes = { "*.mjcf.xml", "*.mujoco.xml" },
  },
  diagnostics = {
    enabled = true,
    python = nil,
    timeout = 20000,
  },
}

function M.plugin_root()
  local src = debug.getinfo(1, "S").source:gsub("^@", "")
  return vim.fn.fnamemodify(src, ":p:h:h:h")
end

function M.bundled_schema_path()
  return M.plugin_root() .. "/schema/" .. M.SCHEMA_NAME
end

local function validate_strings(name, list)
  for i, item in ipairs(list) do
    if type(item) ~= "string" or item == "" then
      error(("%s[%d] must be a non-empty string"):format(name, i))
    end
  end
end

local function validate(opts)
  vim.validate("opts", opts, "table")
  vim.validate("schema_path", opts.schema_path, "string", true)
  vim.validate("schema", opts.schema, "table")
  vim.validate("schema.enabled", opts.schema.enabled, "boolean")
  vim.validate("schema.globs", opts.schema.globs, "table")
  vim.validate("schema.suffixes", opts.schema.suffixes, "table")
  vim.validate("diagnostics", opts.diagnostics, "table")
  vim.validate("diagnostics.enabled", opts.diagnostics.enabled, "boolean")
  vim.validate("diagnostics.python", opts.diagnostics.python, "string", true)
  vim.validate("diagnostics.timeout", opts.diagnostics.timeout, "number")
  if opts.diagnostics.timeout <= 0 then
    error("diagnostics.timeout must be > 0")
  end
  validate_strings("schema.globs", opts.schema.globs)
  validate_strings("schema.suffixes", opts.schema.suffixes)
end

function M.resolve(user)
  if user ~= nil then
    vim.validate("opts", user, "table")
  end
  local opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user or {})
  validate(opts)
  if opts.schema_path and opts.schema_path ~= "" then
    opts.schema_path = vim.fs.normalize(vim.fn.fnamemodify(opts.schema_path, ":p"))
  else
    opts.schema_path = vim.fs.normalize(M.bundled_schema_path())
  end
  opts.diagnostics.timeout = math.floor(opts.diagnostics.timeout)
  return opts
end

function M.file_sha256(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  if not data then
    return nil
  end
  return vim.fn.sha256(data)
end

return M
