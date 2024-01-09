local mod = RegisterMod('Item Wisp Challenge', 1)
local json = require('json')
local game = Game()

mod.stopReplacingItemsWithWisps = false
mod.onGameStartHasRun = false
mod.summonableItems = nil
mod.glitchedItems = nil
mod.glitchedIdx = -1

mod.lemegetonAutoProcOptions = { 'never', 'sacrifice room', 'any damage' }
mod.rngShiftIdx = 35

mod.state = {}
-- true puts wisps into 3 rings around the player w/ a max number of 26
-- false allows an unlimited number in a single ring
-- if true, if you quit/continue then any current wisps will behave like false
-- Lemegeton uses true
mod.state.adjustOrbitLayer = true
mod.state.maxHitPoints = 4          -- 4-16
mod.state.lemegetonFromStart = true -- basement/womb
mod.state.lemegetonPercent = 0      -- 0-25
mod.state.lemegetonAutoProc = 'never'

function mod:onGameStart(isContinue)
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      for _, v in ipairs({ 'adjustOrbitLayer', 'lemegetonFromStart' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
      end
      if math.type(state.maxHitPoints) == 'integer' and state.maxHitPoints >= 4 and state.maxHitPoints <= 16 then
        mod.state.maxHitPoints = state.maxHitPoints
      end
      if math.type(state.lemegetonPercent) == 'integer' and state.lemegetonPercent >= 0 and state.lemegetonPercent <= 25 then
        mod.state.lemegetonPercent = state.lemegetonPercent
      end
      if type(state.lemegetonAutoProc) == 'string' and mod:tblHasVal(mod.lemegetonAutoProcOptions, state.lemegetonAutoProc) then
        mod.state.lemegetonAutoProc = state.lemegetonAutoProc
      end
    end
  end
  
  -- the game doesn't remember modified MaxHitPoints if you continue after shutting down the game
  if isContinue and mod:isChallenge() then
    for _, v in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP, -1, false, false)) do
      v.MaxHitPoints = mod.state.maxHitPoints
    end
  end
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit()
  mod:save()
  mod.stopReplacingItemsWithWisps = false
  mod.onGameStartHasRun = false
  mod.summonableItems = nil
  mod.glitchedItems = nil
  mod.glitchedIdx = -1
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

function mod:onNewRoom()
  if not mod:isChallenge() then
    return
  end
  
  if not mod.onGameStartHasRun then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  mod.stopReplacingItemsWithWisps = false
  
  if room:IsFirstVisit() and (mod.state.lemegetonFromStart or stage >= LevelStage.STAGE4_1) then -- womb/corpse
    local rng = RNG()
    rng:SetSeed(room:GetSpawnSeed(), mod.rngShiftIdx)
    
    if rng:RandomInt(100) < mod.state.lemegetonPercent then
      mod:giveSingleUseLemegeton()
    end
  end
end

-- filtered to 0-Player
function mod:onPlayerUpdate(player)
  if not mod:isChallenge() then
    return
  end
  
  if not mod.onGameStartHasRun or mod.stopReplacingItemsWithWisps then
    return
  end
  
  mod:replaceItemsWithWisps(player)
end

-- filtered to ITEM_WISP
function mod:onFamiliarUpdate(familiar)
  if not mod:isChallenge() then
    return
  end
  
  if not mod.onGameStartHasRun then
    return
  end
  
  if familiar.MaxHitPoints ~= mod.state.maxHitPoints then
    familiar.HitPoints = familiar.HitPoints * mod.state.maxHitPoints / familiar.MaxHitPoints
    familiar.MaxHitPoints = mod.state.maxHitPoints
    --print(familiar.HitPoints .. '/' .. familiar.MaxHitPoints)
  end
end

--filtered to ENTITY_PLAYER
function mod:onEntityTakeDmg(entity, amount, dmgFlags, source, countdown)
  if not mod:isChallenge() then
    return
  end
  
  local room = game:GetRoom()
  local player = entity:ToPlayer()
  
  if mod.state.lemegetonAutoProc == 'sacrifice room' then
    -- source.Type == EntityType.ENTITY_NULL and source.Variant == GridEntityType.GRID_SPIKES
    if room:GetType() == RoomType.ROOM_SACRIFICE and dmgFlags & DamageFlag.DAMAGE_SPIKES == DamageFlag.DAMAGE_SPIKES then
      player:UseActiveItem(CollectibleType.COLLECTIBLE_LEMEGETON, false, false, true, false, -1, 0)
    end
  elseif mod.state.lemegetonAutoProc == 'any damage' then
    -- the animation doesn't work from here, likely because it's displaying the hit animation
    player:UseActiveItem(CollectibleType.COLLECTIBLE_LEMEGETON, false, false, true, false, -1, 0)
  end
end

-- filtered to COLLECTIBLE_GENESIS
function mod:onUseItem(collectible, rng, player, useFlags, activeSlot, varData)
  if not mod:isChallenge() then
    return
  end
  
  mod.stopReplacingItemsWithWisps = true
  
  for _, v in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP, -1, false, false)) do
    local familiar = v:ToFamiliar()
    local player = familiar.Player
    player:AddCollectible(familiar.SubType, 0, false, nil, 0)
  end
end

-- usage: item-wisp-challenge-hp
-- usage: item-wisp-challenge-hp name
-- usage: item-wisp-challenge-hp name percent
function mod:onExecuteCmd(cmd, params)
  if not mod:isInGame() then
    return
  end
  
  cmd = string.lower(cmd)
  params = string.lower(params)
  
  if cmd == 'item-wisp-challenge-hp' then
    local itemConfig = Isaac.GetItemConfig()
    
    local tokenizedParams = {}
    for token in string.gmatch(params, '[%S]+') do -- split on whitespace
      table.insert(tokenizedParams, token)
    end
    
    local familiars = {}
    local itemWisps = {}
    
    -- use GetRoomEntities over FindByType so we can query everything
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
      if entity.Type == EntityType.ENTITY_FAMILIAR then
        local familiar = entity:ToFamiliar()
        table.insert(familiars, familiar)
        
        if entity.Variant == FamiliarVariant.ITEM_WISP then
          table.insert(itemWisps, familiar)
        end
      end
    end
    
    local s = '[Familiars:' .. #familiars .. '/64](Item Wisps:' .. #itemWisps .. ')'
    
    for i = 0, game:GetNumPlayers() - 1 do
      local player = game:GetPlayer(i)
      local playerHash = GetPtrHash(player)
      local playerLabel, playerType
      if player:GetBabySkin() ~= BabySubType.BABY_UNASSIGNED then
        playerLabel = 'Baby'
        playerType = player:GetBabySkin()
      else
        playerLabel = player.Parent == nil and 'Player' or 'Child'
        playerType = player:GetPlayerType()
      end
      local itemWispCount = 0
      local itemWispStr = ''
      
      for _, itemWisp in ipairs(itemWisps) do
        if playerHash == GetPtrHash(itemWisp.Player) then
          local c, hp
          local collectibleConfig = itemConfig:GetCollectible(itemWisp.SubType)
          if mod:tblHasVal(tokenizedParams, 'name') then
            -- technically label in repentance
            c = collectibleConfig and collectibleConfig.Name or itemWisp.SubType
          else
            -- gives negative numbers for glitched items
            c = collectibleConfig and collectibleConfig.ID or itemWisp.SubType
          end
          if mod:tblHasVal(tokenizedParams, 'percent') then
            hp = string.format('%.2f', itemWisp.HitPoints / itemWisp.MaxHitPoints)
          else
            hp = string.format('%.1f/%.1f', itemWisp.HitPoints, itemWisp.MaxHitPoints)
          end
          local hid = itemWisp:HasEntityFlags(EntityFlag.FLAG_NO_QUERY) and '*' or ''
          itemWispStr = itemWispStr .. '(' .. c .. ':' .. hp .. hid .. ')'
          itemWispCount = itemWispCount + 1
        end
      end
      
      s = s .. '\n[' .. i .. '-' .. playerLabel .. ':' .. player.ControllerIndex .. ':' .. playerType .. ':' .. itemWispCount .. ']' .. itemWispStr
    end
    
    print(s)
    Isaac.DebugString('item-wisp-challenge-hp\n' .. s)
  end
end

function mod:isInGame()
  if REPENTOGON then
    return Isaac.IsInGame()
  end
  
  return true
end

function mod:giveSingleUseLemegeton()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    player:SetPocketActiveItem(CollectibleType.COLLECTIBLE_LEMEGETON, ActiveSlot.SLOT_POCKET2, true)
    player:AnimateCollectible(CollectibleType.COLLECTIBLE_LEMEGETON, 'UseItem', 'PlayerPickupSparkle')
  end
end

function mod:replaceItemsWithWisps(player)
  if mod.summonableItems == nil then
    mod.summonableItems = mod:getSummonableItems()
  end
  
  -- normal items
  for _, item in ipairs(mod.summonableItems) do
    mod:replaceItemWithWisp(player, item)
  end
  
  -- known glitched items
  if mod.glitchedItems then
    for _, item in ipairs(mod.glitchedItems) do
      mod:replaceItemWithWisp(player, item)
    end
  end
  
  -- new glitched items
  for _, item in ipairs(mod:getNewGlitchedItems()) do
    if mod.glitchedItems == nil then
      mod.glitchedItems = {}
    end
    table.insert(mod.glitchedItems, item)
    mod:replaceItemWithWisp(player, item)
  end
end

function mod:replaceItemWithWisp(player, item)
  while player:HasCollectible(item, true) do -- ignore wisps
    player:RemoveCollectible(item, true, nil, true) -- ActiveSlot.SLOT_PRIMARY
    player:AddItemWisp(item, player.Position, mod.state.adjustOrbitLayer)
  end
end

function mod:getSummonableItems()
  local itemConfig = Isaac.GetItemConfig()
  local items = {}
  
  -- 0 is CollectibleType.COLLECTIBLE_NULL
  for i = 1, #itemConfig:GetCollectibles() - 1 do
    local collectibleConfig = itemConfig:GetCollectible(i)
    
    -- some numbers don't exist
    -- can Lemegeton summon the item?
    if collectibleConfig and collectibleConfig:HasTags(ItemConfig.TAG_SUMMONABLE) then
      table.insert(items, collectibleConfig.ID)
    end
  end
  
  return items
end

function mod:getNewGlitchedItems()
  local itemConfig = Isaac.GetItemConfig()
  local items = {}
  
  -- 4294967295 == -1
  -- 4294967294 == -2
  local collectibleConfig = itemConfig:GetCollectible(mod.glitchedIdx)
  while collectibleConfig do
    -- filter active items
    -- summonable tag won't be set, but Lemegeton can still spawn passive glitched items
    if collectibleConfig.Type ~= ItemType.ITEM_ACTIVE then
      table.insert(items, collectibleConfig.ID)
    end
    
    mod.glitchedIdx = mod.glitchedIdx - 1
    collectibleConfig = itemConfig:GetCollectible(mod.glitchedIdx)
  end
  
  return items
end

function mod:getTblIdx(tbl, val)
  for i, v in ipairs(tbl) do
    if v == val then
      return i
    end
  end
  
  return 0
end

function mod:tblHasVal(tbl, val)
  return mod:getTblIdx(tbl, val) > 0
end

function mod:isChallenge()
  local challenge = Isaac.GetChallenge()
  return challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (Mom)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (It Lives)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (Mother)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (Blue Baby)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (The Lamb)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (Mega Satan)')
end

function mod:setupEid()
  EID:addDescriptionModifier(mod.Name .. ' - Collectible' , function(descObj)
    if mod:isChallenge() and descObj.ObjType == EntityType.ENTITY_PICKUP and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE then
      local itemConfig = Isaac.GetItemConfig()
      local collectibleConfig = itemConfig:GetCollectible(descObj.ObjSubType)
      if collectibleConfig and
         (
           collectibleConfig:HasTags(ItemConfig.TAG_SUMMONABLE) or
           (collectibleConfig.ID < 0 and collectibleConfig.Type ~= ItemType.ITEM_ACTIVE) -- glitched
         )
      then
        return true
      end
    end
    return false
  end, function(descObj)
    -- english only for now
    EID:appendToDescription(descObj, '#{{Collectible712}} Lemegeton can summon this item')
    return descObj
  end)
  
  EID:addDescriptionModifier(mod.Name .. ' - Sacrifice Room', function(descObj)
    local room = game:GetRoom()
    return mod:isChallenge() and room:GetType() == RoomType.ROOM_SACRIFICE and descObj.ObjType == -999 and descObj.ObjVariant == -1 and
           mod.state.lemegetonAutoProc ~= 'never'
  end, function(descObj)
    EID:appendToDescription(descObj, '#{{Collectible712}} Lemegeton will be triggered')
    return descObj
  end)
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'Wisps', 'Lemegeton' }) do
    ModConfigMenu.RemoveSubcategory(mod.Name, v)
  end
  ModConfigMenu.AddText(mod.Name, 'Wisps', 'Items converted into wisps')
  ModConfigMenu.AddText(mod.Name, 'Wisps', 'should orbit the player in:')
  ModConfigMenu.AddSpace(mod.Name, 'Wisps')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Wisps',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.adjustOrbitLayer
      end,
      Display = function()
        return mod.state.adjustOrbitLayer and '3 layers' or '1 layer'
      end,
      OnChange = function(b)
        mod.state.adjustOrbitLayer = b
        mod:save()
      end,
      Info = { '1: limited to 64 total familiars', '3: lemegeton behavior / limited to 26 wisps' }
    }
  )
  ModConfigMenu.AddSpace(mod.Name, 'Wisps')
  ModConfigMenu.AddText(mod.Name, 'Wisps', 'Max health:')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Wisps',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod.state.maxHitPoints
      end,
      Minimum = 4,
      Maximum = 16,
      Display = function()
        return string.format('%.1f (%d%%)', mod.state.maxHitPoints, mod.state.maxHitPoints / 4 * 100)
      end,
      OnChange = function(n)
        mod.state.maxHitPoints = n
        mod:save()
      end,
      Info = { '100% - 400%', 'Item wisp max health' }
    }
  )
  ModConfigMenu.AddText(mod.Name, 'Lemegeton', 'Single-use lemegeton should be given:')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Lemegeton',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod.state.lemegetonPercent
      end,
      Minimum = 0,
      Maximum = 25,
      Display = function()
        return mod.state.lemegetonPercent .. '% of the time'
      end,
      OnChange = function(n)
        mod.state.lemegetonPercent = n
        mod:save()
      end,
      Info = { 'Calculated on your first visit to each room' }
    }
  )
  ModConfigMenu.AddSpace(mod.Name, 'Lemegeton')
  ModConfigMenu.AddText(mod.Name, 'Lemegeton', 'Starting in the:')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Lemegeton',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.lemegetonFromStart
      end,
      Display = function()
        return mod.state.lemegetonFromStart and 'basement' or 'womb'
      end,
      OnChange = function(b)
        mod.state.lemegetonFromStart = b
        mod:save()
      end,
      Info = { 'Basement: basement, cellar, burning basement', 'Womb: womb, utero, scarred womb, corpse' }
    }
  )
  ModConfigMenu.AddSpace(mod.Name, 'Lemegeton')
  ModConfigMenu.AddText(mod.Name, 'Lemegeton', 'Auto-proc lemegeton:')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Lemegeton',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getTblIdx(mod.lemegetonAutoProcOptions, mod.state.lemegetonAutoProc)
      end,
      Minimum = 1,
      Maximum = #mod.lemegetonAutoProcOptions,
      Display = function()
        return mod.state.lemegetonAutoProc
      end,
      OnChange = function(n)
        mod.state.lemegetonAutoProc = mod.lemegetonAutoProcOptions[n]
        mod:save()
      end,
      Info = { 'Do you want to automatically trigger lemegeton', 'in sacrifice rooms or for any damage?' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.onPlayerUpdate, 0) -- 0 is player, 1 is co-op baby
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.onFamiliarUpdate, FamiliarVariant.ITEM_WISP)
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.onEntityTakeDmg, EntityType.ENTITY_PLAYER)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.onUseItem, CollectibleType.COLLECTIBLE_GENESIS)
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, mod.onExecuteCmd)

if EID then
  mod:setupEid()
end
if ModConfigMenu then
  mod:setupModConfigMenu()
end

if REPENTOGON then
  function mod:registerCommands()
    Console.RegisterCommand('item-wisp-challenge-hp', 'Prints/logs item wisp health (supports name and percent params)', 'Prints/logs item wisp health (supports name and percent params)', false, AutocompleteType.NONE)
  end
  
  mod:registerCommands()
end