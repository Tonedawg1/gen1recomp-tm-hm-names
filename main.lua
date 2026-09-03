return function(mod)
  local MAX_LEN = 12   -- safe width for bag / PC list rows

  local patched = 0

  for id, item in mod.content.items:each() do
    local machine = item.machine
    if machine and machine.kind and machine.number and machine.move then
      local move = mod.content.moves:get(machine.move)
      if move and move.name then
        local prefix = (machine.kind == "HM") and "HM" or "TM"
        local base = string.format("%s%02d ", prefix, machine.number)  -- e.g. "TM15 "
        local moveName = move.name
        local full = base .. moveName

        if #full > MAX_LEN then
          local available = MAX_LEN - #base - 1  -- leave room for the period
          if available < 1 then available = 1 end
          moveName = moveName:sub(1, available) .. "."
          full = base .. moveName
        end

        if item.name ~= full then
          mod.content.items:patch(id, { name = full })
          patched = patched + 1
        end
      end
    end
  end

  mod.log:info("TM/HM names: updated %d machines (max %d chars)", patched, MAX_LEN)
end
