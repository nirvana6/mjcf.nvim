local M = {}

local function bundled_report()
  local config = require("mjcf.config")
  local path = config.bundled_schema_path()
  if vim.fn.filereadable(path) ~= 1 then
    vim.health.error("bundled schema missing: " .. path)
    return
  end
  local got = config.file_sha256(path)
  if got == config.EXPECTED_SHA256 then
    vim.health.ok("schema " .. path .. " sha256 matches 4.0.1")
  else
    vim.health.error(
      "schema sha256 mismatch for "
        .. path
        .. " (got "
        .. tostring(got)
        .. ", expected "
        .. config.EXPECTED_SHA256
        .. ")"
    )
  end
end

function M.check()
  vim.health.start("mjcf")

  local version = vim.version()
  local ver = string.format("%d.%d.%d", version.major, version.minor, version.patch)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim " .. ver)
  else
    vim.health.error("Neovim " .. ver .. " is older than 0.11; L1 schema binding is skipped")
  end

  if vim.fn.executable("lemminx") == 1 then
    local enabled = vim.lsp.is_enabled("lemminx") and "enabled" or "not enabled"
    vim.health.ok("lemminx is executable (" .. enabled .. ")")
  else
    vim.health.warn("lemminx is not executable; schema associations stay inert until it is installed")
  end

  bundled_report()
  local active = require("mjcf").get_config()
  local bundled = vim.fs.normalize(require("mjcf.config").bundled_schema_path())
  if active and vim.fs.normalize(active.schema_path) ~= bundled then
    if vim.fn.filereadable(active.schema_path) == 1 then
      vim.health.info("schema_path override: " .. active.schema_path)
    else
      vim.health.error("schema_path override is missing: " .. active.schema_path)
    end
  end

  local opts = active or require("mjcf.config").resolve({})
  local ok, found_or_err = pcall(function()
    return require("mjcf.diagnostics").discover(vim.api.nvim_get_current_buf(), opts)
  end)
  if not ok then
    vim.health.error("python probe failed: " .. tostring(found_or_err))
  elseif not found_or_err then
    vim.health.warn("python: no interpreter with importable mujoco")
  else
    vim.health.ok(
      "python: " .. found_or_err.display .. " (mujoco " .. found_or_err.version .. ")"
    )
  end

  vim.health.info("L2 (name completion): planned")
  local blink = vim.api.nvim_get_runtime_file("lua/blink/cmp/init.lua", false)
  if #blink > 0 then
    vim.health.info("blink.cmp: found")
  else
    vim.health.info("blink.cmp: not found")
  end
end

return M
