local actualLove = love

local function appendOutput(output, ...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  output[#output + 1] = table.concat(parts, "\t")
end

local function writeReport(ok, script, err, output)
  local path = os.getenv("POKEPORT_TEST_RESULT")
  if not path or path == "" then return end

  local report, openErr = io.open(path, "wb")
  if not report then
    io.stderr:write("could not write test report: ", tostring(openErr), "\n")
    return
  end

  if ok then
    report:write("OK\n")
  else
    report:write("FAIL\n", tostring(err or "unknown test failure"), "\n")
  end
  if #output > 0 then
    report:write("OUTPUT\n")
    for _, line in ipairs(output) do
      report:write(line, "\n")
    end
  end
  report:close()
end

function love.load()
  package.path = "./?.lua;./?/init.lua;" .. package.path

  local output = {}
  local realPrint = print
  print = function(...)
    appendOutput(output, ...)
  end

  local script = os.getenv("POKEPORT_TEST_SCRIPT")
  if not script or script == "" then
    local err = "POKEPORT_TEST_SCRIPT is required"
    writeReport(false, "<unset>", err, output)
    print = realPrint
    actualLove.event.quit(1)
    return
  end

  _G.POKEPORT_TEST_CHILD = true
  _G.love = nil

  local realExit = os.exit
  local exitSentinel = {}
  os.exit = function(code)
    error({ sentinel = exitSentinel, code = tonumber(code) or 0 }, 0)
  end

  local ok, err = xpcall(function()
    dofile(script)
  end, function(value)
    if type(value) == "table" and value.sentinel == exitSentinel then
      return value
    end
    return debug.traceback(tostring(value), 2)
  end)

  os.exit = realExit
  _G.love = actualLove
  print = realPrint

  if not ok and type(err) == "table" and err.sentinel == exitSentinel then
    ok = err.code == 0
    if not ok then err = "suite exited with status " .. tostring(err.code) end
  end

  writeReport(ok, script, err, output)
  actualLove.event.quit(ok and 0 or 1)
end
