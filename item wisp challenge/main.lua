local mod = RegisterMod('Item Wisp Challenge', 1)
local json = require('json')
local game = Game()

mod.onGameStartHasRun = false
mod.summonableItems = nil
mod.glitchedIdx = -1
mod.rngShiftIdx = 35

mod.state = {}
-- true puts wisps into 3 rings around the player w/ a max number of 26
-- false allows an unlimited number in a single ring
-- if true, if you quit/continue then any current wisps will behave like false
-- Lemegeton uses true
mod.state.adjustOrbitLayer = true
mod.state.lemegetonFromStart = true -- basement/womb
mod.state.lemegetonPercent = 0      -- 0-15

function mod:onGameStart()
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if type(state.adjustOrbitLayer) == 'boolean' then
        mod.state.adjustOrbitLayer = state.adjustOrbitLayer
      end
      if type(state.lemegetonFromStart) == 'boolean' then
        mod.state.lemegetonFromStart = state.lemegetonFromStart
      end
      if math.type(state.lemegetonPercent) == 'integer' and state.lemegetonPercent >= 0 and state.lemegetonPercent <= 15 then
        mod.state.lemegetonPercent = state.lemegetonPercent
      end
    end
  end
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit()
  mod:save()
  mod.onGameStartHasRun = false
  mod.summonableItems = nil
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
  
  if not mod.onGameStartHasRun then
    return
  end
  
  mod:replaceItemsWithWisps(player)
end

function mod:giveSingleUseLemegeton()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    player:SetPocketActiveItem(CollectibleType.COLLECTIBLE_LEMEGETON, ActiveSlot.SLOT_POCKET2, true)
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
  
  -- glitched items
  -- 4294967295 == -1
  -- 4294967294 == -2
  local itemConfig = Isaac.GetItemConfig()
  local collectibleConfig = itemConfig:GetCollectible(mod.glitchedIdx)
  while collectibleConfig do
    -- filter active items
    -- summonable tag won't be set, but Lemegeton can still spawn passive glitched items
    if collectibleConfig.Type ~= ItemType.ITEM_ACTIVE then
      table.insert(mod.summonableItems, collectibleConfig.ID)
      mod:replaceItemWithWisp(player, collectibleConfig.ID)
    end
    
    mod.glitchedIdx = mod.glitchedIdx - 1
    collectibleConfig = itemConfig:GetCollectible(mod.glitchedIdx)
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
  
  for i = 0, #itemConfig:GetCollectibles() - 1 do
    local collectibleConfig = itemConfig:GetCollectible(i)
    
    -- some numbers don't exist
    -- can Lemegeton summon the item?
    if collectibleConfig and collectibleConfig:HasTags(ItemConfig.TAG_SUMMONABLE) then
      table.insert(items, collectibleConfig.ID)
    end
  end
  
  return items
end

function mod:isChallenge()
  local challenge = Isaac.GetChallenge()
  return challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (Mom)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (It Lives)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (Mother)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (Blue Baby)') or
         challenge == Isaac.GetChallengeIdByName('Item Wisp Challenge (The Lamb)')
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
      Info = { '1: unlimited wisps', '3: lemegeton behavior / limited to 26 wisps' }
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
      Maximum = 15,
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
        return mod.state.lemegetonFromStart and 'Basement' or 'Womb'
      end,
      OnChange = function(b)
        mod.state.lemegetonFromStart = b
        mod:save()
      end,
      Info = { 'Basement: basement, cellar, burning basement', 'Womb: womb, utero, scarred womb, corpse' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.onPlayerUpdate, 0) -- 0 is player, 1 is co-op baby

if ModConfigMenu then
  mod:setupModConfigMenu()
end