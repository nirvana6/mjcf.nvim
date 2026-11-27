local M = {}

local state = {
  config = nil,
  l1 = "disabled",
  version_notified = false,
}

function M.get_config()
  return state.config
end

function M.l1_status()
  return state.l1
end

function M.setup(opts)
  local config = require("mjcf.config").resolve(opts)
  state.config = config

  if not config.schema.enabled then
    state.l1 = "disabled"
  elseif vim.fn.has("nvim-0.11") == 0 then
    state.l1 = "skipped"
    if not state.version_notified then
      state.version_notified = true
      vim.notify(
        "mjcf: Neovim 0.11+ is required for schema binding; skipping L1",
        vim.log.levels.WARN
      )
    end
  else
    require("mjcf.schema").register(config)
    state.l1 = "enabled"
  end

  require("mjcf.diagnostics").setup(config)
end

local function emit(lines)
  local text = table.concat(lines, "\n")
  print(text)
  return text
end

function M.info()
  if not state.config then
    return emit({ "mjcf.nvim: not set up" })
  end
  local config = state.config
  local diagnostics = require("mjcf.diagnostics")
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local lemminx_exec = vim.fn.executable("lemminx") == 1 and "executable" or "not executable"
  local lemminx_on = vim.lsp.is_enabled("lemminx") and "enabled" or "not enabled"
  local l1 = state.l1
  if l1 == "skipped" then
    l1 = "skipped (nvim < 0.11)"
  end
  local l3 = config.diagnostics.enabled and "enabled" or "disabled"
  return emit({
    "mjcf.nvim",
    "L1 schema: " .. l1,
    "schema: " .. config.schema_path,
    "lemminx: " .. lemminx_exec .. ", " .. lemminx_on,
    "L2 references: planned",
    "L3 diagnostics: " .. l3,
    "python: " .. (config.diagnostics.enabled and diagnostics.describe(buf) or "disabled"),
    "buffer: " .. (name ~= "" and name or "[No Name]"),
    "mjcf: " .. (vim.b[buf].mjcf and "yes" or "no"),
    "diagnostics running: " .. (diagnostics.is_running(buf) and "yes" or "no"),
  })
end

function M.restart()
  if vim.fn.exists(":LspRestart") == 2 then
    vim.cmd("LspRestart lemminx")
    return
  end
  vim.notify(
    "mjcf: :LspRestart is unavailable; enable lemminx again so fileAssociations reload",
    vim.log.levels.WARN
  )
end

function M.diag()
  if not state.config then
    vim.notify("mjcf: not set up", vim.log.levels.WARN)
    return
  end
  if not state.config.diagnostics.enabled then
    vim.notify("mjcf: diagnostics are disabled", vim.log.levels.INFO)
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local diagnostics = require("mjcf.diagnostics")
  if not vim.b[buf].mjcf and not diagnostics.consider(buf) then
    vim.notify("mjcf: current buffer is not MJCF", vim.log.levels.INFO)
    return
  end
  diagnostics.compile(buf, { force = true })
end

return M
