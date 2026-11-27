local dir = (arg[0] or "tests/detect_spec.lua"):match("^(.*)/") or "tests"
local H = dofile(dir .. "/harness.lua")
local detect = require("mjcf.detect")

local seq = 0
local function unique_name(name, n)
  local function splice(suffix)
    return name:sub(1, #name - #suffix) .. "-" .. n .. suffix
  end
  if name:sub(-11) == ".mujoco.xml" then
    return splice(".mujoco.xml")
  end
  if name:sub(-9) == ".mjcf.xml" then
    return splice(".mjcf.xml")
  end
  if name:sub(-4) == ".xml" then
    return splice(".xml")
  end
  return name .. "-" .. n
end

local function buf_with(name, lines, ft)
  seq = seq + 1
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(buf, unique_name(name, seq))
  if ft ~= nil then
    vim.bo[buf].filetype = ft
  end
  return buf
end

local root = buf_with("/tmp/mjcf-detect-root.xml", { "<mujoco>" }, "xml")
H.check(detect.is_mjcf(root), "<mujoco> in the first screen")

local indented = buf_with("/tmp/mjcf-detect-indent.xml", { '   <mujoco model="ur5e">' }, "xml")
H.check(detect.is_mjcf(indented), "indented <mujoco ...> in the first screen")

local other = buf_with("/tmp/mjcf-detect-other.xml", {
  "<launch>",
  '  <arg name="foo"/>',
  "</launch>",
}, "xml")
H.check(not detect.is_mjcf(other), "non-MJCF xml is ignored")

local suffix = buf_with("/tmp/mjcf-detect-named.mjcf.xml", { "<robot/>" }, "")
H.check(detect.is_mjcf(suffix), ".mjcf.xml suffix is MJCF without a mujoco root")

local suffix2 = buf_with("/tmp/mjcf-detect-named.mujoco.xml", { "<robot/>" }, "xml")
H.check(detect.is_mjcf(suffix2), ".mujoco.xml suffix is MJCF without a mujoco root")

local late = {}
for i = 1, 200 do
  late[i] = "<!-- not yet -->"
end
late[201] = "<mujoco>"
local past = buf_with("/tmp/mjcf-detect-late.xml", late, "xml")
H.check(not detect.is_mjcf(past), "<mujoco> past line 200 is ignored")

late[200] = "<mujoco>"
local edge = buf_with("/tmp/mjcf-detect-edge.xml", late, "xml")
H.check(detect.is_mjcf(edge), "<mujoco> on line 200 counts")

local py = buf_with("/tmp/mjcf-detect-py.py", { 's = "<mujoco>"' }, "python")
H.check(not detect.is_mjcf(py), "non-xml filetype is ignored")

H.finish()
