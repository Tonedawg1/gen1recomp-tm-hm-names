return function(mod)
  local MAX_CHARS = 12       -- Gen 1 bag / PC item-box rows (unchanged)
  local MAX_CHARS_MART = 14  -- Gen 2 mart name row (price is on the next line)
  -- ScriptMenu Game Corner rows: ~13 tiles for "TM25 … 5500" (menu to col 15)
  local MAX_CHARS_SCRIPT = 13

  mod.options:define({
    {
      key = "ticker",
      type = "toggle",
      label = "SCROLL LONG NAMES",
      default = true,
    },
  })

  ----------------------------------------------------------------
  -- Full names on the items registry (both gens)
  ----------------------------------------------------------------
  local patched = 0
  for id, item in mod.content.items:each() do
    local full = nil

    local machine = item.machine
    if machine and machine.kind and machine.number and machine.move then
      local move = mod.content.moves:get(machine.move)
      if move and move.name then
        local prefix = (machine.kind == "HM") and "HM" or "TM"
        full = string.format("%s%02d %s", prefix, machine.number, move.name)
      end
    elseif item.teaches and type(item.name) == "string" then
      local kind, num = item.name:match("^(TM)(%d+)$")
      if not kind then
        kind, num = item.name:match("^(HM)(%d+)$")
      end
      if kind and num then
        local move = mod.content.moves:get(item.teaches)
        if move and move.name then
          full = string.format("%s%02d %s", kind, tonumber(num), move.name)
        end
      end
    end

    if full and item.name ~= full then
      mod.content.items:patch(id, { name = full })
      patched = patched + 1
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

  local function displayLabel(full, tick, scrollMove, maxChars)
    maxChars = maxChars or MAX_CHARS
    local prefix, move = splitMachineLabel(full)
    local room = maxChars - #prefix
    if room < 1 then room = 1 end

    if #prefix + #move <= maxChars then
      return full
    end

    if scrollMove then
      return prefix .. Marquee.at(move, room, tick or 0)
    end

    if #move <= room then
      return prefix .. move
    end
    if room <= 1 then
      return prefix .. "."
    end
    return prefix .. move:sub(1, room - 1) .. "."
  end

  local function isMachineLabel(s)
    return type(s) == "string"
      and (s:match("^TM%d%d%s+") ~= nil or s:match("^HM%d%d%s+") ~= nil)
  end

  -- Fixed Game Corner TM → move (Gold / Silver / Crystal, both cities)
  local GAME_CORNER_MOVES = {
    ["TM32"] = "DOUBLE TEAM",
    ["TM29"] = "PSYCHIC",
    ["TM15"] = "HYPER BEAM",
    ["TM25"] = "THUNDER",
    ["TM14"] = "BLIZZARD",
    ["TM38"] = "FIRE BLAST",
  }

  ----------------------------------------------------------------
  -- GEN 1: ListMenu decoration (bag / PC / Gen 1 shops)
  ----------------------------------------------------------------
  local function decorateList(list)
    if not list or list.__tm_hm_names_decorated then return end
    list.__tm_hm_names_decorated = true

    local vanillaUpdate = list.update
    list.update = function(self, dt)
      local step = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
      local useTicker = mod.options:get("ticker")
      local idx = self.index

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
              it.label = displayLabel(it.__tm_hm_full, it.__tm_hm_tick or 0, scrollThis, MAX_CHARS)
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

  local okList, ListMenu = pcall(require, "src.ui.ListMenu")
  if okList and ListMenu and ListMenu.new and not ListMenu.__tm_hm_names_wrapped then
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

  ----------------------------------------------------------------
  -- GEN 2: MartMenu (normal shops)
  ----------------------------------------------------------------
  local okMart, MartMenu = pcall(require, "src.ui.gen2.MartMenu")
  if okMart and MartMenu and not MartMenu.__tm_hm_names_wrapped then
    MartMenu.__tm_hm_names_wrapped = true

    local vanillaUpdate = MartMenu.update
    MartMenu.update = function(self, dt)
      local step = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
      if self.phase == "buy" and mod.options:get("ticker") then
        local idx = self.index
        if self.__tm_hm_last_index ~= idx then
          self.__tm_hm_last_index = idx
          local entry = self.entries and self.entries[idx]
          if entry then entry.__tm_hm_tick = 0 end
        end
        local entry = self.entries and self.entries[idx]
        if entry then
          local full = entry.__tm_hm_full or entry.name
          if isMachineLabel(full) then
            local prefix, move = splitMachineLabel(full)
            if #prefix + #move > MAX_CHARS_MART then
              entry.__tm_hm_tick = (entry.__tm_hm_tick or 0) + step
            end
          end
        end
      end
      if vanillaUpdate then return vanillaUpdate(self, dt) end
    end

    local vanillaDrawBuyList = MartMenu.drawBuyList
    MartMenu.drawBuyList = function(self)
      local saved = {}
      local useTicker = mod.options:get("ticker")
      local idx = self.index

      for i, entry in ipairs(self.entries or {}) do
        local name = entry.name
        if isMachineLabel(name) or entry.__tm_hm_full then
          if not entry.__tm_hm_full then entry.__tm_hm_full = name end
          if #entry.__tm_hm_full > MAX_CHARS_MART then
            saved[i] = name
            local scrollThis = useTicker and (i == idx)
            entry.name = displayLabel(
              entry.__tm_hm_full, entry.__tm_hm_tick or 0, scrollThis, MAX_CHARS_MART)
          end
        end
      end

      if vanillaDrawBuyList then vanillaDrawBuyList(self) end

      for i, orig in pairs(saved) do
        if self.entries[i] then self.entries[i].name = orig end
      end
    end

    mod.log:info("TM/HM names: MartMenu wrap installed (Gen 2 shops)")
  end

  ----------------------------------------------------------------
  -- GEN 2: ScriptMenu — THIS is what Game Corner actually draws
  -- Header items look like "TM25 5500" (name + price in one string)
  ----------------------------------------------------------------
  local okScript, ScriptMenu = pcall(require, "src.ui.gen2.ScriptMenu")
  if okScript and ScriptMenu and not ScriptMenu.__tm_hm_names_wrapped then
    ScriptMenu.__tm_hm_names_wrapped = true

    -- Expand "TM25 5500" → name side + price, truncate/scroll the name side
    local function expandScriptLabel(label, tick, scrollThis)
      if type(label) ~= "string" then return label end
      local tm, price = label:match("^(TM%d%d)%s+(%d+)$")
      if not tm then return label end
      local move = GAME_CORNER_MOVES[tm]
      if not move then return label end

      local fullName = string.format("%s %s", tm, move) -- "TM25 THUNDER"
      local pricePart = tostring(price)
      -- Leave one space before the price digits
      local nameBudget = MAX_CHARS_SCRIPT - #pricePart - 1
      if nameBudget < #tm + 1 then nameBudget = #tm + 1 end

      local shown = displayLabel(fullName, tick, scrollThis, nameBudget)
      local pad = nameBudget - #shown
      if pad < 0 then pad = 0 end
      return shown .. string.rep(" ", pad) .. " " .. pricePart
    end

    local function isGameCornerTmLabel(label)
      if type(label) ~= "string" then return false end
      local tm = label:match("^(TM%d%d)%s+%d+$")
      return tm ~= nil and GAME_CORNER_MOVES[tm] ~= nil
    end

    local vanillaNew = ScriptMenu.new
    ScriptMenu.new = function(game, opts)
      local menu = vanillaNew(game, opts)
      -- Snapshot originals so draw can rebuild each frame for the ticker
      if menu and menu.items then
        menu.__tm_hm_orig_items = {}
        for i, label in ipairs(menu.items) do
          menu.__tm_hm_orig_items[i] = label
        end
        menu.__tm_hm_ticks = {}
        menu.__tm_hm_last_index = nil
      end
      return menu
    end

    local vanillaUpdate = ScriptMenu.update
    ScriptMenu.update = function(self, dt)
      local step = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
      if mod.options:get("ticker") and self.__tm_hm_orig_items then
        local idx = ScriptMenu.choiceIndex(self.row, self.col, self.cols)
        if self.__tm_hm_last_index ~= idx then
          self.__tm_hm_last_index = idx
          self.__tm_hm_ticks[idx] = 0
        end
        local orig = self.__tm_hm_orig_items[idx]
        if isGameCornerTmLabel(orig) then
          self.__tm_hm_ticks[idx] = (self.__tm_hm_ticks[idx] or 0) + step
        end
      end
      if vanillaUpdate then return vanillaUpdate(self, dt) end
    end

    local vanillaDrawPanel = ScriptMenu.drawPanel
    ScriptMenu.drawPanel = function(self)
      local saved = nil
      if self.__tm_hm_orig_items then
        saved = {}
        local useTicker = mod.options:get("ticker")
        local idx = ScriptMenu.choiceIndex(self.row, self.col, self.cols)
        for i, orig in ipairs(self.__tm_hm_orig_items) do
          if isGameCornerTmLabel(orig) then
            saved[i] = self.items[i]
            local scrollThis = useTicker and (i == idx)
            local tick = (self.__tm_hm_ticks and self.__tm_hm_ticks[i]) or 0
            self.items[i] = expandScriptLabel(orig, tick, scrollThis)
          end
        end
      end

      if vanillaDrawPanel then vanillaDrawPanel(self) end

      if saved then
        for i, orig in pairs(saved) do
          self.items[i] = orig
        end
      end
    end

    mod.log:info("TM/HM names: ScriptMenu wrap installed (Gen 2 Game Corner)")
  end
end
