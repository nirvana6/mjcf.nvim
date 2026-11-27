local detect = require("mjcf.detect")
local parser = require("mjcf.parser")

local M = {}

local COMPILE_SNIPPET = "import sys, mujoco; mujoco.MjModel.from_xml_path(sys.argv[1])"
local VERIFY_SNIPPET = "import mujoco; print(mujoco.__version__)"
local NS = vim.api.nvim_create_namespace("mjcf.diagnostics")

local config
local attached = {}
local inflight = {}
local job_gen = {}
local result_cache = {}
local python_cache
local python_notified = false

local function start_dir(buf)
  if buf and buf ~= 0 and vim.api.nvim_buf_is_valid(buf) then
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
      return vim.fn.fnamemodify(name, ":p:h")
    end
  end
  return vim.fn.getcwd()
end

local function project_root(start)
  local dir = start
  local guard = 0
  while type(dir) == "string" and dir ~= "" and guard < 64 do
    guard = guard + 1
    if vim.uv.fs_stat(dir .. "/pyproject.toml") or vim.uv.fs_stat(dir .. "/.git") then
      return dir
    end
    if dir == "/" then
      break
    end
    local parent = dir:match("^(.*)/[^/]+$")
    if not parent or parent == dir then
      break
    end
    dir = parent
  end
  return nil
end

local function verify(argv)
  local cmd = vim.list_extend(vim.deepcopy(argv), { "-c", VERIFY_SNIPPET })
  local ok, result = pcall(function()
    return vim.system(cmd, { text = true, timeout = 20000 }):wait()
  end)
  if not ok or type(result) ~= "table" or result.code ~= 0 then
    return nil
  end
  local version
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      version = trimmed
    end
  end
  if not version or not version:match("^%d") then
    return nil
  end
  return version
end

local function candidates(buf, opts)
  local list = {}
  local python = opts.diagnostics.python
  if type(python) == "string" and python ~= "" then
    list[#list + 1] = { argv = { python }, display = python }
  end
  local root = project_root(start_dir(buf))
  if root then
    local venv = root .. "/.venv/bin/python"
    list[#list + 1] = { argv = { venv }, display = venv }
    if vim.uv.fs_stat(root .. "/pyproject.toml") and vim.fn.executable("uv") == 1 then
      list[#list + 1] = {
        argv = { "uv", "run", "--project", root, "python" },
        display = "uv run --project " .. root .. " python",
      }
    end
  end
  list[#list + 1] = { argv = { "python3" }, display = "python3" }
  return list
end

function M.invalidate_python_cache()
  python_cache = nil
end

function M.discover(buf, opts)
  opts = opts or config
  if python_cache ~= nil then
    return python_cache or nil
  end
  if not opts then
    opts = require("mjcf.config").resolve({})
  end
  for _, cand in ipairs(candidates(buf, opts)) do
    local version = verify(cand.argv)
    if version then
      python_cache = {
        argv = cand.argv,
        display = cand.display,
        version = version,
      }
      return python_cache
    end
  end
  python_cache = false
  return nil
end

function M.describe(buf)
  local found = M.discover(buf or vim.api.nvim_get_current_buf())
  if not found then
    return "unavailable"
  end
  return string.format("%s (mujoco %s)", found.display, found.version)
end

function M.is_running(buf)
  return inflight[buf] ~= nil
end

local function cache_key(path)
  local st = vim.uv.fs_stat(path)
  if not st or not st.mtime then
    return nil
  end
  return string.format("%s\0%d\0%d\0%d", path, st.mtime.sec or 0, st.mtime.nsec or 0, st.size or 0)
end

local function notify_python_once()
  if python_notified then
    return
  end
  python_notified = true
  vim.notify(
    "mjcf: no Python with importable mujoco found; diagnostics are disabled",
    vim.log.levels.WARN
  )
end

local function kill_job(buf)
  local old = inflight[buf]
  inflight[buf] = nil
  if type(old) == "table" and type(old.kill) == "function" then
    pcall(function()
      old:kill("sigterm")
    end)
  end
end

function M.clear(buf)
  job_gen[buf] = (job_gen[buf] or 0) + 1
  kill_job(buf)
  attached[buf] = nil
  pcall(vim.diagnostic.reset, NS, buf)
end

function M.attach(buf)
  if attached[buf] then
    return
  end
  attached[buf] = true
  local group = vim.api.nvim_create_augroup("mjcf", { clear = false })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = buf,
    callback = function()
      M.compile(buf, { force = false })
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      M.clear(buf)
    end,
  })
end

function M.consider(buf)
  if not detect.is_mjcf(buf) then
    return false
  end
  vim.b[buf].mjcf = true
  M.attach(buf)
  return true
end

local function apply(buf, diags)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.diagnostic.set(NS, buf, diags)
  end
end

function M.compile(buf, opts)
  opts = opts or {}
  if not config or not config.diagnostics.enabled then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.fn.filereadable(path) ~= 1 then
    return
  end

  local key = cache_key(path)
  if key and not opts.force and result_cache[key] then
    apply(buf, vim.deepcopy(result_cache[key]))
    return
  end

  local gen = (job_gen[buf] or 0) + 1
  job_gen[buf] = gen
  kill_job(buf)

  local py = M.discover(buf)
  if not py then
    notify_python_once()
    return
  end

  local timeout = config.diagnostics.timeout
  local cmd = vim.list_extend(vim.deepcopy(py.argv), { "-c", COMPILE_SNIPPET, path })
  local finished = false
  local ok, obj = pcall(vim.system, cmd, { text = false, timeout = timeout }, function(result)
    if job_gen[buf] ~= gen then
      return
    end
    finished = true
    inflight[buf] = nil
    vim.schedule(function()
      if job_gen[buf] ~= gen or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local diags
      if result.code == 124 then
        diags = {
          {
            lnum = 0,
            col = 0,
            severity = vim.diagnostic.severity.WARN,
            source = "mjcf",
            message = string.format("mjcf: compile timed out after %dms", timeout),
          },
        }
      elseif result.code == 0 then
        diags = {}
        if key then
          result_cache[key] = {}
        end
      else
        local stderr = type(result.stderr) == "string" and result.stderr or ""
        diags = parser.parse(stderr, path)
        if key then
          result_cache[key] = vim.deepcopy(diags)
        end
      end
      apply(buf, diags)
    end)
  end)

  if not ok then
    notify_python_once()
    return
  end
  if not finished and job_gen[buf] == gen then
    inflight[buf] = obj
  end
end

function M.setup(opts)
  config = opts
  M.invalidate_python_cache()
  for buf, obj in pairs(inflight) do
    job_gen[buf] = (job_gen[buf] or 0) + 1
    if type(obj) == "table" and type(obj.kill) == "function" then
      pcall(function()
        obj:kill("sigterm")
      end)
    end
  end
  local group = vim.api.nvim_create_augroup("mjcf", { clear = true })
  inflight = {}
  attached = {}
  if not opts.diagnostics.enabled then
    return
  end
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    callback = function(ev)
      M.consider(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      M.invalidate_python_cache()
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.consider(buf)
    end
  end
end

return M
