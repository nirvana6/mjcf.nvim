local dir = (arg[0] or "tests/parser_spec.lua"):match("^(.*)/") or "tests"
local H = dofile(dir .. "/harness.lua")
local parser = require("mjcf.parser")

local function fixture(name)
  return H.read(H.root .. "/tests/fixtures/" .. name)
end

local pad = "/tmp/mjcf-parser-pad.xml"
do
  local f = assert(io.open(pad, "wb"))
  for i = 1, 500 do
    f:write("<!-- " .. i .. " -->\n")
  end
  f:close()
end

local cases = {
  { file = "xml_syntax.txt", line = 3, needle = "XML_ERROR_MISMATCHED_ELEMENT" },
  { file = "undefined_default_class.txt", line = 4, needle = "no_such_class" },
  { file = "range_without_limited.txt", line = 5, needle = "range" },
  { file = "mesh_missing.txt", line = 1, needle = "does_not_exist.obj" },
  { file = "actuator_missing_joint.txt", line = 9, needle = "missing_joint" },
  { file = "tendon_missing_joint.txt", line = 10, needle = "missing_tendon_joint" },
  { file = "include_missing.txt", line = 2, needle = "missing_child.xml", prefix = "missing_child.xml:" },
  { file = "duplicate_body.txt", line = 6, needle = "repeated name" },
}

for _, case in ipairs(cases) do
  local diags = parser.parse(fixture(case.file), pad)
  H.eq(#diags, 1, case.file .. " yields one diagnostic")
  if diags[1] then
    H.eq(diags[1].lnum + 1, case.line, case.file .. " line")
    H.contains(diags[1].message, case.needle, case.file .. " message")
    if case.prefix then
      H.check(diags[1].message:sub(1, #case.prefix) == case.prefix, case.file .. " filename prefix")
    end
  end
end

local clamp_path = "/tmp/mjcf-parser-clamp.xml"
do
  local f = assert(io.open(clamp_path, "wb"))
  f:write("<mujoco>\n</mujoco>\n")
  f:close()
end
local clamped = parser.parse(fixture("range_without_limited.txt"), clamp_path)
H.eq(#clamped, 1, "clamp yields one diagnostic")
if clamped[1] then
  H.eq(clamped[1].lnum + 1, 2, "line beyond EOF clamps to last line")
end

H.eq(#parser.parse("", pad), 0, "empty stderr")

H.finish()
