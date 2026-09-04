return function(mod)
  local MAX_CHARS = 12  -- total visible width for bag / PC item-box rows

  mod.options:define({
    {
      key = "ticker",
      type = "toggle",
      label = "SCROLL LONG NAMES",
      default = true,
    },
  })

  -- Always store the FULL name. Truncate vs scroll is display-only.
  local patched = 0
  for id, item in mod.content.items:each() do
    local machine = item.machine
    if machine and machine.kind and machine.number and machine.move then
      local move = mod.content.moves:get(machine.move)
      if move and move.name then
        local prefix = (machine.kind == "HM") and "HM" or "TM"
        local full = string.format("%s%02d %s", prefix, machine.number, move.name)
        if item.name ~= full then
          mod.content.items:patch(id, { name = full })
          patched = patched + 1
        end
      end
    end
  end
  mod.log:info("TM/HM names: set full names on %d machines", patched)

  local Marquee = require("src.ui.Marquee")

  local function splitMachineLabel(label)
    local prefix, move = label:match("^(TM%d%d%s+)(.+)$")
    if not prefix then
      prefix, move = label:match("^(HM%d%d%s+)(.+)$")
    end
    if prefix and move then
      return prefix, move
    end
    return "", label
  end

  -- scrollMove = true only for the highlighted row when the option is on
  local function displayLabel(full, tick, scrollMove)
    local prefix, move = splitMachineLabel(full)
    local room = MAX_CHARS - #prefix
    if room < 1 then room = 1 end

    if #prefix + #move <= MAX_CHARS then
      return full
    end

    if scrollMove then
      return prefix .. Marquee.at(move, room, tick or 0)
    end

    -- Static / non-highlighted: pin prefix, clip move name
    if #move <= room then
      return prefix .. move
    end
    if room <= 1 then
      return prefix .. "."
    end
    return prefix .. move:sub(1, room - 1) .. "."
  end

  local function decorateList(list)
    if not list or list.__tm_hm_names_decorated then return end
    list.__tm_hm_names_decorated = true

    local vanillaUpdate = list.update
    list.update = function(self, dt)
      local step = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
      local useTicker = mod.options:get("ticker")
      local idx = self.index

      -- Reset scroll phase when the cursor moves to a new row
      if self.__tm_hm_last_index ~= idx then
        self.__tm_hm_last_index = idx
        local it = self.items and self.items[idx]
        if it then it.__tm_hm_tick = 0 end
      end

      if useTicker then
        local it = self.items and self.items[idx]
        if it then
          local full = it.__tm_hm_full or it.label
          if type(full) == "string" then
            local prefix, move = splitMachineLabel(full)
            if #prefix + #move > MAX_CHARS then
              it.__tm_hm_tick = (it.__tm_hm_tick or 0) + step
            end
          end
        end
      end

      if vanillaUpdate then return vanillaUpdate(self, dt) end
    end

    local function prepareLabels(self)
      local saved = {}
      local useTicker = mod.options:get("ticker")
      local idx = self.index

      for i, it in ipairs(self.items or {}) do
        local label = it.label
        if type(label) == "string" then
          local prefix = label:match("^TM%d%d%s+") or label:match("^HM%d%d%s+")
          if prefix or it.__tm_hm_full then
            if not it.__tm_hm_full then it.__tm_hm_full = label end
            if #it.__tm_hm_full > MAX_CHARS then
              saved[i] = label
              local scrollThis = useTicker and (i == idx)
              it.label = displayLabel(it.__tm_hm_full, it.__tm_hm_tick or 0, scrollThis)
            end
          end
        end
      end
      return saved
    end

    local function restoreLabels(self, saved)
      for i, orig in pairs(saved) do
        if self.items[i] then self.items[i].label = orig end
      end
    end

    if list.drawItemBox then
      local vanillaItemBox = list.drawItemBox
      list.drawItemBox = function(self, ...)
        local saved = prepareLabels(self)
        vanillaItemBox(self, ...)
        restoreLabels(self, saved)
      end
    end

    local vanillaDraw = list.draw
    list.draw = function(self, ...)
      local saved = prepareLabels(self)
      if vanillaDraw then vanillaDraw(self, ...) end
      restoreLabels(self, saved)
    end
  end

  local ok, ListMenu = pcall(require, "src.ui.ListMenu")
  if ok and ListMenu and ListMenu.new and not ListMenu.__tm_hm_names_wrapped then
    ListMenu.__tm_hm_names_wrapped = true
    local vanillaNew = ListMenu.new
    ListMenu.new = function(game, title, items, opts)
      local list = vanillaNew(game, title, items, opts)
      decorateList(list)
      return list
    end
    mod.log:info("TM/HM names: ListMenu ticker wrap installed (cursor-only scroll)")
  else
    mod.log:warn("TM/HM names: could not wrap ListMenu; display fallback only")
  end
end
