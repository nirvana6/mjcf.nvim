local dir = (arg[0] or "tests/diagnostics_spec.lua"):match("^(.*)/") or "tests"
local H = dofile(dir .. "/harness.lua")

local env_project = vim.env.MJCF_TEST_PROJECT
local project
if type(env_project) == "string" and env_project ~= "" then
  project = env_project
else
  project = vim.fn.expand("~/Documents/Github_Official_Repo/MuJoCo_Project")
end
project = project:gsub("/+$", "")
local py = project .. "/.venv/bin/python"
if vim.fn.isdirectory(project) ~= 1 or vim.fn.executable(py) ~= 1 then
  print("SKIP diagnostics_spec: project fixture not found (" .. project .. ")")
  print("RESULT 0 0")
  io.stdout:flush()
  return
end

local src_xml = project .. "/model/universal_robots_ur5e/ur5e.xml"
local src_assets = project .. "/model/universal_robots_ur5e/assets"
local dir_tmp = "/tmp/mjcf-nvim-diag-test"
local dst = dir_tmp .. "/ur5e.xml"

vim.fn.delete(dir_tmp, "rf")
vim.fn.mkdir(dir_tmp, "p")

local text = H.read(src_xml)
local old = table.concat({
  '      <default class="size3">',
  '        <default class="size3_limited">',
  '          <joint range="-3.1415 3.1415"/>',
  '          <general ctrlrange="-3.1415 3.1415"/>',
  '        </default>',
  '      </default>',
}, "\n")
local new = table.concat({
  '      <default class="size3">',
  '      </default>',
}, "\n")
local at, end_at = text:find(old, 1, true)
H.check(at ~= nil, "found size3_limited default in the /tmp copy")
local broken = text
if at then
  broken = text:sub(1, at - 1) .. new .. text:sub(end_at + 1)
end

local out = assert(io.open(dst, "wb"))
out:write(broken)
out:close()

local linked = vim.uv.fs_symlink(src_assets, dir_tmp .. "/assets")
H.check(linked ~= nil, "assets symlink for meshdir")

local probed = vim
  .system({ py, "-c", "import sys, mujoco; mujoco.MjModel.from_xml_path(sys.argv[1])", dst }, { text = true })
  :wait()
local expected
for line_no in (probed.stderr or ""):gmatch("line (%d+)") do
  expected = tonumber(line_no)
end
H.check(expected ~= nil and expected > 1, "mujoco reported a line (" .. tostring(expected) .. ")")
H.contains(probed.stderr or "", "size3_limited", "mujoco reported the deleted default class")
if not (expected and expected > 1) then
  H.finish()
  return
end

require("mjcf").setup({
  diagnostics = {
    python = py,
    timeout = 30000,
  },
})

vim.cmd("edit " .. vim.fn.fnameescape(dst))
local buf = vim.api.nvim_get_current_buf()
H.check(vim.b[buf].mjcf == true, "opened ur5e copy is detected as MJCF")

vim.bo[buf].modified = true
vim.cmd("silent write")

local waited = vim.wait(40000, function()
  return #vim.diagnostic.get(buf) > 0
end, 20)
local diags = vim.diagnostic.get(buf)
H.check(waited and #diags > 0, "diagnostics arrived after :write (" .. #diags .. ")")
if diags[1] then
  H.eq(diags[1].lnum + 1, expected, "diagnostic line matches MuJoCo")
  H.contains(diags[1].message, "size3_limited", "diagnostic message names the missing class")
end

H.finish()
