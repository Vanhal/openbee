local version = {
  ["major"] = 2,
  ["minor"] = 4,
  ["patch"] = 0
}

-- for logLine function calls to improve readability
local alwaysShow = true
-- how often should it output dots after waiting on apiary
-- default is every 5th check
local logSkip = 5

-- default colors
local defaultText = colors.white
local defaultBack = colors.black

function loadFile(fileName)
  local f = fs.open(fileName, "r")
  if f ~= nil then
    local data = f.readAll()
    f.close()
    return textutils.unserialize(data)
  end
end

function saveFile(fileName, data)
  local f = fs.open(fileName, "w")
  f.write(textutils.serialize(data))
  f.close()
end

local config = loadFile("bee.config")
if config == nil then
  config = {
    ["apiaryType"] = "normal",
    ["apiarySide"] = "left",
    ["chestSide"] = "top",
    ["chestDir"] = "up",
    ["productDir"] = "down",
    ["analyzerDir"] = "east",
    ["ignoreSpecies"] = {
      "Leporine"
    },
	["warningColor"] = colors.orange,
	["targetColor"] = colors.green,
	["detailedOutput"] = true,
	["monitor"] = nil
  }
  saveFile("bee.config", config)
  
-- backward compatibility with old config files: assume defaults for new configs
else
	config.warningColor = config.warningColor or colors.orange
	config.targetColor = config.targetColor or colors.green
	config.monitor = config.monitor or nil
	
	if config.detailedOutput == nil then
	  config.detailedOutput = true
	end
end

local useAnalyzer = true
local useReferenceBees = true

local traitPriority = {
  "speciesChance", 
  "speed", 
  "fertility", 
  "nocturnal", 
  "tolerantFlyer", 
  "caveDwelling", 
  "temperatureTolerance", 
  "humidityTolerance", 
  "effect", 
  "flowering", 
  "flowerProvider", 
  "territory"
}

function setPriorities(priority)
  local species = nil
  local priorityNum = 1
  for traitNum, trait in ipairs(priority) do
    local found = false
    for traitPriorityNum = 1, #traitPriority do
      if trait == traitPriority[traitPriorityNum] then
        found = true
        if priorityNum ~= traitPriorityNum then
          table.remove(traitPriority, traitPriorityNum)
          table.insert(traitPriority, priorityNum, trait)
        end
        priorityNum = priorityNum + 1
        break
      end
    end
    if not found then
      species = trait
    end
  end
  return species
end

-- logging ----------------------------

local logFile
function setupLog()
  local logCount = 0
  while fs.exists(string.format("bee.%d.log", logCount)) do
    logCount = logCount + 1
  end
  logFile = fs.open(string.format("bee.%d.log", logCount), "w")
  return string.format("bee.%d.log", logCount)
end

function log(msg, txtColor, bkgdColor)
  msg = msg or ""
  logFile.write(tostring(msg))
  logFile.flush()
  
  if term.isColor() then
	  txtColor = txtColor or defaultText
	  bkgdColor = bkgdColor or defaultBack
	  term.setTextColor(txtColor)
	  term.setBackgroundColor(bkgdColor)
	  io.write(msg)
	  term.setTextColor(defaultText)
	  term.setBackgroundColor(defaultBack)
  else
    io.write(msg)
  end
end

function logLine(toConsole, ...)
  for i, msg in ipairs(arg) do
    if msg == nil then
      msg = ""
    end
    logFile.write(msg)
	if toConsole then
	  io.write(msg)
	end
  end
  logFile.write("\n")
  logFile.flush()
  if toConsole then
    io.write("\n")
  end
end

function logLineColor(txtColor, bkgdColor, ...)
	if term.isColor() then
		term.setTextColor(txtColor)
		term.setBackgroundColor(bkgdColor)
		logLine(...)
		term.setTextColor(defaultText)
		term.setBackgroundColor(defaultBack)
	else
		logLine(...)
	end
end

function getPeripherals()
  local names = table.concat(peripheral.getNames(), ", ")
  local chestPeripheral = peripheral.wrap(config.chestSide)
  if chestPeripheral == nil then
    error("Bee chest not found at " .. config.chestSide .. ".  Valid config values are " .. names .. ".")
  end
  local apiaryPeripheral = peripheral.wrap(config.apiarySide)
  if apiaryPeripheral == nil then
    error("Apiary not found at " .. config.apiarySide .. ".  Valid config values are " .. names .. ".")
  end
  -- check config directions
  if not pcall(function () chestPeripheral.pullItem(config.analyzerDir, 9) end) then
    logLine(alwaysShow, "Analyzer direction incorrect.  Direction should be relative to bee chest.")
    useAnalyzer = false
  end
  return chestPeripheral, apiaryPeripheral
end

-- utility functions ------------------

function choose(list1, list2)
  local newList = {}
  if list2 then
    for i = 1, #list2 do
      for j = 1, #list1 do
        if list1[j] ~= list2[i] then
          table.insert(newList, {list1[j], list2[i]})
        end
      end
    end
  else
    for i = 1, #list1 do
      for j = i, #list1 do
        if list1[i] ~= list1[j] then
          table.insert(newList, {list1[i], list1[j]})
        end
      end
    end
  end
  return newList
end

-- fix for yet another API change from openp
function getAllBees(inv)
  local notbees = inv.getAllStacks()
  local bees = {}
  for slot, bee in pairs(notbees) do
    bees[slot] = bee.all()
  end
  return bees
end

function getBeeInSlot(inv, slot)
  return inv.getStackInSlot(slot)
end

-- fix for some versions returning bees.species.*
local nameFix = {}
function fixName(name)
  if type(name) == "table" then
    name = name.name
  end
  local newName = name:gsub("bees%.species%.",""):gsub("^.", string.upper)
  if name ~= newName then
    nameFix[newName] = name
  end
  return newName
end

function fixBee(bee)
  if bee.individual ~= nil then
    bee.individual.displayName = fixName(bee.individual.displayName)
    if bee.individual.isAnalyzed then
      bee.individual.active.species.name = fixName(bee.individual.active.species.name)
      bee.individual.inactive.species.name = fixName(bee.individual.inactive.species.name)
    end
  end
  return bee
end

function fixParents(parents)
  parents.allele1 = fixName(parents.allele1)
  parents.allele2 = fixName(parents.allele2)
  if parents.result then
    parents.result = fixName(parents.result)
  end
  return parents
end

function beeName(bee)
  if bee.individual.active then
    return bee.slot .. "=" .. bee.individual.active.species.name:sub(1,3) .. "-" ..
                              bee.individual.inactive.species.name:sub(1,3)
  else
    return bee.slot .. "=" .. bee.individual.displayName:sub(1,3)
  end
end

function printBee(bee)
  if bee.individual.isAnalyzed then
    local active = bee.individual.active
    local inactive = bee.individual.inactive
    if active.species.name ~= inactive.species.name then
      log(string.format("%s-%s", active.species.name, inactive.species.name))
    else
      log(active.species.name)
    end
    if bee.raw_name == "item.for.beedronege" then
      log(" Drone")
    elseif bee.raw_name == "item.for.beeprincessge" then
      log(" Princess")
    else
      log(" Queen")
    end
    --log((active.nocturnal and " Nocturnal" or " "))
    --log((active.tolerantFlyer and " Flyer" or " "))
    --log((active.caveDwelling and " Cave" or " "))
    logLine(alwaysShow)
    --logLine(string.format("Fert: %d  Speed: %d  Lifespan: %d", active.fertility, active.speed, active.lifespan))
  else
  end
end

-- mutations and scoring --------------

function getBeeBreedingData()
  breedingTable = {}
  breedingTable[1] = {
    ['allele1'] = "Forest",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[2] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[3] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[4] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[5] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[6] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[7] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[8] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[9] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[10] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[11] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[12] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[13] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[14] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[15] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[16] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[17] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[18] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[19] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[20] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[21] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Marshy",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[22] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Noble",
    ['chance'] = 10
   }
  breedingTable[23] = {
    ['allele1'] = "Noble",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Majestic",
    ['chance'] = 8
   }
  breedingTable[24] = {
    ['allele1'] = "Noble",
    ['specialConditions'] = {},
    ['allele2'] = "Majestic",
    ['result'] = "Imperial",
    ['chance'] = 8
   }
  breedingTable[25] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Diligent",
    ['chance'] = 10
   }
  breedingTable[26] = {
    ['allele1'] = "Diligent",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Unweary",
    ['chance'] = 8
   }
  breedingTable[27] = {
    ['allele1'] = "Diligent",
    ['specialConditions'] = {},
    ['allele2'] = "Unweary",
    ['result'] = "Industrious",
    ['chance'] = 8
   }
  breedingTable[28] = {
    ['allele1'] = "Steadfast",
    ['specialConditions'] = {[1] = "Is restricted to FOREST-like environments."},
    ['allele2'] = "Valiant",
    ['result'] = "Heroic",
    ['chance'] = 6
   }
  breedingTable[29] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {[1] = "Is restricted to NETHER-like environments."},
    ['allele2'] = "Cultivated",
    ['result'] = "Sinister",
    ['chance'] = 60
   }
  breedingTable[30] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Sinister",
    ['chance'] = 60
   }
  breedingTable[31] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Fiendish",
    ['chance'] = 40
   }
  breedingTable[32] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Fiendish",
    ['chance'] = 40
   }
  breedingTable[33] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Fiendish",
    ['chance'] = 40
   }
  breedingTable[34] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Fiendish",
    ['result'] = "Demonic",
    ['chance'] = 25
   }
  breedingTable[35] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {
      [1] = "Temperature between WARM and HOT.",
      [2] = "Humidity ARID required.",
      },
    ['allele2'] = "Sinister",
    ['result'] = "Frugal",
    ['chance'] = 16
   }
  breedingTable[36] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Fiendish",
    ['result'] = "Frugal",
    ['chance'] = 10
   }
  breedingTable[37] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Frugal",
    ['result'] = "Austere",
    ['chance'] = 8
   }
  breedingTable[38] = {
    ['allele1'] = "Austere",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Exotic",
    ['chance'] = 12
   }
  breedingTable[39] = {
    ['allele1'] = "Exotic",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Edenic",
    ['chance'] = 8
   }
  breedingTable[40] = {
    ['allele1'] = "Industrious",
    ['specialConditions'] = {[1] = "Temperature between ICY and COLD."},
    ['allele2'] = "Wintry",
    ['result'] = "Icy",
    ['chance'] = 12
   }
  breedingTable[41] = {
    ['allele1'] = "Icy",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Glacial",
    ['chance'] = 8
   }
  breedingTable[42] = {
    ['allele1'] = "Meadows",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Leporine",
    ['chance'] = 10
   }
  breedingTable[43] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Merry",
    ['chance'] = 10
   }
  breedingTable[44] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Tipsy",
    ['chance'] = 10
   }
  breedingTable[45] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "Tricky",
    ['chance'] = 10
   }
  breedingTable[46] = {
    ['allele1'] = "Meadows",
    ['specialConditions'] = {[1] = "Is restricted to PLAINS-like environments."},
    ['allele2'] = "Diligent",
    ['result'] = "Rural",
    ['chance'] = 12
   }
  breedingTable[47] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Austere",
    ['result'] = "Secluded",
    ['chance'] = 12
   }
  breedingTable[48] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Secluded",
    ['result'] = "Hermitic",
    ['chance'] = 8
   }
  breedingTable[49] = {
    ['allele1'] = "Hermitic",
    ['specialConditions'] = {},
    ['allele2'] = "Ender",
    ['result'] = "Spectral",
    ['chance'] = 4
   }
  breedingTable[50] = {
    ['allele1'] = "Spectral",
    ['specialConditions'] = {},
    ['allele2'] = "Ender",
    ['result'] = "Phantasmal",
    ['chance'] = 2
   }
  breedingTable[51] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Demonic",
    ['result'] = "Vindictive",
    ['chance'] = 4
   }
  breedingTable[52] = {
    ['allele1'] = "Demonic",
    ['specialConditions'] = {},
    ['allele2'] = "Vindictive",
    ['result'] = "Vengeful",
    ['chance'] = 8
   }
  breedingTable[53] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Vindictive",
    ['result'] = "Vengeful",
    ['chance'] = 8
   }
  breedingTable[54] = {
    ['allele1'] = "Vengeful",
    ['specialConditions'] = {},
    ['allele2'] = "Vindictive",
    ['result'] = "Avenging",
    ['chance'] = 4
   }
  breedingTable[55] = {
    ['allele1'] = "Meadows",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Arid",
    ['chance'] = 10
   }
  breedingTable[56] = {
    ['allele1'] = "Arid",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "Barren",
    ['chance'] = 8
   }
  breedingTable[57] = {
    ['allele1'] = "Arid",
    ['specialConditions'] = {},
    ['allele2'] = "Barren",
    ['result'] = "Desolate",
    ['chance'] = 8
   }
  breedingTable[58] = {
    ['allele1'] = "Barren",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Gnawing",
    ['chance'] = 15
   }
  breedingTable[59] = {
    ['allele1'] = "Desolate",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Decaying",
    ['chance'] = 15
   }
  breedingTable[60] = {
    ['allele1'] = "Desolate",
    ['specialConditions'] = {},
    ['allele2'] = "Frugal",
    ['result'] = "Skeletal",
    ['chance'] = 15
   }
  breedingTable[61] = {
    ['allele1'] = "Desolate",
    ['specialConditions'] = {},
    ['allele2'] = "Austere",
    ['result'] = "Creepy",
    ['chance'] = 15
   }
  breedingTable[62] = {
    ['allele1'] = "Gnawing",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "Decomposing",
    ['chance'] = 15
   }
  breedingTable[63] = {
    ['allele1'] = "Rocky",
    ['specialConditions'] = {},
    ['allele2'] = "Diligent",
    ['result'] = "Tolerant",
    ['chance'] = 15
   }
  breedingTable[64] = {
    ['allele1'] = "Rocky",
    ['specialConditions'] = {},
    ['allele2'] = "Tolerant",
    ['result'] = "Robust",
    ['chance'] = 15
   }
  breedingTable[65] = {
    ['allele1'] = "Imperial",
    ['specialConditions'] = {},
    ['allele2'] = "Robust",
    ['result'] = "Resilient",
    ['chance'] = 15
   }
  breedingTable[66] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Rusty",
    ['chance'] = 5
   }
  breedingTable[67] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Corroded",
    ['chance'] = 5
   }
  breedingTable[68] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Marshy",
    ['result'] = "Tarnished",
    ['chance'] = 5
   }
  breedingTable[69] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Unweary",
    ['result'] = "Leaden",
    ['chance'] = 5
   }
  breedingTable[70] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Unweary",
    ['result'] = "Lustered",
    ['chance'] = 10
   }
  breedingTable[71] = {
    ['allele1'] = "Rusty",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Shining",
    ['chance'] = 2
   }
  breedingTable[72] = {
    ['allele1'] = "Corroded",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Glittering",
    ['chance'] = 2
   }
  breedingTable[73] = {
    ['allele1'] = "Glittering",
    ['specialConditions'] = {},
    ['allele2'] = "Shining",
    ['result'] = "Valuable",
    ['chance'] = 2
   }
  breedingTable[74] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Water",
    ['result'] = "Lapis",
    ['chance'] = 5
   }
  breedingTable[75] = {
    ['allele1'] = "Lapis",
    ['specialConditions'] = {},
    ['allele2'] = "Noble",
    ['result'] = "Emerald",
    ['chance'] = 5
   }
  breedingTable[76] = {
    ['allele1'] = "Emerald",
    ['specialConditions'] = {},
    ['allele2'] = "Austere",
    ['result'] = "Ruby",
    ['chance'] = 5
   }
  breedingTable[77] = {
    ['allele1'] = "Emerald",
    ['specialConditions'] = {},
    ['allele2'] = "Ocean",
    ['result'] = "Sapphire",
    ['chance'] = 5
   }
  breedingTable[78] = {
    ['allele1'] = "Lapis",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Diamond",
    ['chance'] = 5
   }
  breedingTable[79] = {
    ['allele1'] = "Austere",
    ['specialConditions'] = {},
    ['allele2'] = "Rocky",
    ['result'] = "Unstable",
    ['chance'] = 5
   }
  breedingTable[80] = {
    ['allele1'] = "Unstable",
    ['specialConditions'] = {},
    ['allele2'] = "Rusty",
    ['result'] = "Nuclear",
    ['chance'] = 5
   }
  breedingTable[81] = {
    ['allele1'] = "Nuclear",
    ['specialConditions'] = {},
    ['allele2'] = "Glittering",
    ['result'] = "Radioactive",
    ['chance'] = 5
   }
  breedingTable[82] = {
    ['allele1'] = "Noble",
    ['specialConditions'] = {},
    ['allele2'] = "Diligent",
    ['result'] = "Ancient",
    ['chance'] = 10
   }
  breedingTable[83] = {
    ['allele1'] = "Ancient",
    ['specialConditions'] = {},
    ['allele2'] = "Noble",
    ['result'] = "Primeval",
    ['chance'] = 8
   }
  breedingTable[84] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Majestic",
    ['result'] = "Prehistoric",
    ['chance'] = 8
   }
  breedingTable[85] = {
    ['allele1'] = "Prehistoric",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Relic",
    ['chance'] = 8
   }
  breedingTable[86] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Growing",
    ['result'] = "Fossilised",
    ['chance'] = 8
   }
  breedingTable[87] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Fungal",
    ['result'] = "Resinous",
    ['chance'] = 8
   }
  breedingTable[88] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Ocean",
    ['result'] = "Oily",
    ['chance'] = 8
   }
  breedingTable[89] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Boggy",
    ['result'] = "Preserved",
    ['chance'] = 8
   }
  breedingTable[90] = {
    ['allele1'] = "Oily",
    ['specialConditions'] = {},
    ['allele2'] = "Industrious",
    ['result'] = "Distilled",
    ['chance'] = 8
   }
  breedingTable[91] = {
    ['allele1'] = "Oily",
    ['specialConditions'] = {},
    ['allele2'] = "Distilled",
    ['result'] = "Refined",
    ['chance'] = 8
   }
  breedingTable[92] = {
    ['allele1'] = "Refined",
    ['specialConditions'] = {},
    ['allele2'] = "Fossilised",
    ['result'] = "Tarry",
    ['chance'] = 8
   }
  breedingTable[93] = {
    ['allele1'] = "Refined",
    ['specialConditions'] = {},
    ['allele2'] = "Resinous",
    ['result'] = "Elastic",
    ['chance'] = 8
   }
  breedingTable[94] = {
    ['allele1'] = "Water",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "River",
    ['chance'] = 10
   }
  breedingTable[95] = {
    ['allele1'] = "Water",
    ['specialConditions'] = {
[1] = "Hive needs to be in Ocean",
                            },
    ['allele2'] = "Diligent",
    ['result'] = "Ocean",
    ['chance'] = 10
   }
  breedingTable[96] = {
    ['allele1'] = "Ebony",
    ['specialConditions'] = {},
    ['allele2'] = "Ocean",
    ['result'] = "Stained",
    ['chance'] = 8
   }
  breedingTable[97] = {
    ['allele1'] = "Diligent",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Growing",
    ['chance'] = 10
   }
  breedingTable[98] = {
    ['allele1'] = "Growing",
    ['specialConditions'] = {},
    ['allele2'] = "Rural",
    ['result'] = "Thriving",
    ['chance'] = 10
   }
  breedingTable[99] = {
    ['allele1'] = "Thriving",
    ['specialConditions'] = {},
    ['allele2'] = "Growing",
    ['result'] = "Blooming",
    ['chance'] = 8
   }
  breedingTable[100] = {
     ['allele1'] = "Valiant",
     ['specialConditions'] = {},
     ['allele2'] = "Diligent",
     ['result'] = "Sweetened",
     ['chance'] = 15
    }
  breedingTable[101] = {
     ['allele1'] = "Sweetened",
     ['specialConditions'] = {},
     ['allele2'] = "Diligent",
     ['result'] = "Sugary",
     ['chance'] = 15
    }
  breedingTable[102] = {
     ['allele1'] = "Sugary",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Ripening",
     ['chance'] = 5
    }
  breedingTable[103] = {
     ['allele1'] = "Ripening",
     ['specialConditions'] = {},
     ['allele2'] = "Rural",
     ['result'] = "Fruity",
     ['chance'] = 5
    }
  breedingTable[104] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Rural",
     ['result'] = "Farmed",
     ['chance'] = 10
    }
  breedingTable[105] = {
     ['allele1'] = "Rural",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Bovine",
     ['chance'] = 10
    }
  breedingTable[106] = {
     ['allele1'] = "Tropical",
     ['specialConditions'] = {},
     ['allele2'] = "Rural",
     ['result'] = "Caffeinated",
     ['chance'] = 10
    }
  breedingTable[107] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Damp",
     ['chance'] = 10
    }
  breedingTable[108] = {
     ['allele1'] = "Damp",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Boggy",
     ['chance'] = 8
    }
  breedingTable[109] = {
     ['allele1'] = "Boggy",
     ['specialConditions'] = {},
     ['allele2'] = "Damp",
     ['result'] = "Fungal",
     ['chance'] = 8
    }
  breedingTable[110] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[111] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[112] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[113] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[114] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[115] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[116] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[117] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[118] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[119] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[120] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[121] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[122] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[123] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[124] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[125] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[126] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[127] = {
     ['allele1'] = "Embittered",
     ['specialConditions'] = {},
     ['allele2'] = "Sinister",
     ['result'] = "Furious",
     ['chance'] = 10
    }
  breedingTable[128] = {
     ['allele1'] = "Embittered",
     ['specialConditions'] = {},
     ['allele2'] = "Furious",
     ['result'] = "Volcanic",
     ['chance'] = 6
    }
  breedingTable[129] = {
     ['allele1'] = "Sinister",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Malicious",
     ['chance'] = 10
    }
  breedingTable[130] = {
     ['allele1'] = "Malicious",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Infectious",
     ['chance'] = 8
    }
  breedingTable[131] = {
     ['allele1'] = "Malicious",
     ['specialConditions'] = {},
     ['allele2'] = "Infectious",
     ['result'] = "Virulent",
     ['chance'] = 8
    }
  breedingTable[132] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Exotic",
     ['result'] = "Viscous",
     ['chance'] = 10
    }
  breedingTable[133] = {
     ['allele1'] = "Viscous",
     ['specialConditions'] = {},
     ['allele2'] = "Exotic",
     ['result'] = "Glutinous",
     ['chance'] = 8
    }
  breedingTable[134] = {
     ['allele1'] = "Viscous",
     ['specialConditions'] = {},
     ['allele2'] = "Glutinous",
     ['result'] = "Sticky",
     ['chance'] = 8
    }
  breedingTable[135] = {
     ['allele1'] = "Virulent",
     ['specialConditions'] = {},
     ['allele2'] = "Sticky",
     ['result'] = "Corrosive",
     ['chance'] = 10
    }
  breedingTable[136] = {
     ['allele1'] = "Corrosive",
     ['specialConditions'] = {},
     ['allele2'] = "Fiendish",
     ['result'] = "Caustic",
     ['chance'] = 8
    }
  breedingTable[137] = {
     ['allele1'] = "Corrosive",
     ['specialConditions'] = {},
     ['allele2'] = "Caustic",
     ['result'] = "Acidic",
     ['chance'] = 4
    }
  breedingTable[138] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Excited",
     ['chance'] = 10
    }
  breedingTable[139] = {
     ['allele1'] = "Excited",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Energetic",
     ['chance'] = 8
    }
  breedingTable[140] = {
     ['allele1'] = "Wintry",
     ['specialConditions'] = {},
     ['allele2'] = "Diligent",
     ['result'] = "Frigid",
     ['chance'] = 10
    }
  breedingTable[141] = {
     ['allele1'] = "Ocean",
     ['specialConditions'] = {},
     ['allele2'] = "Frigid",
     ['result'] = "Absolute",
     ['chance'] = 10
    }
  breedingTable[142] = {
     ['allele1'] = "Tolerant",
     ['specialConditions'] = {},
     ['allele2'] = "Sinister",
     ['result'] = "Shadowed",
     ['chance'] = 10
    }
  breedingTable[143] = {
     ['allele1'] = "Shadowed",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Darkened",
     ['chance'] = 8
    }
  breedingTable[144] = {
     ['allele1'] = "Shadowed",
     ['specialConditions'] = {},
     ['allele2'] = "Darkened",
     ['result'] = "Abyssal",
     ['chance'] = 8
    }
  breedingTable[145] = {
     ['allele1'] = "Forest",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Maroon",
     ['chance'] = 5
    }
  breedingTable[146] = {
     ['allele1'] = "Meadows",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Saffron",
     ['chance'] = 5
    }
  breedingTable[147] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Prussian",
     ['chance'] = 5
    }
  breedingTable[148] = {
     ['allele1'] = "Tropical",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Natural",
     ['chance'] = 5
    }
  breedingTable[149] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Ebony",
     ['chance'] = 5
    }
  breedingTable[150] = {
     ['allele1'] = "Wintry",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Bleached",
     ['chance'] = 5
    }
  breedingTable[151] = {
     ['allele1'] = "Marshy",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Sepia",
     ['chance'] = 5
    }
  breedingTable[152] = {
     ['allele1'] = "Maroon",
     ['specialConditions'] = {},
     ['allele2'] = "Saffron",
     ['result'] = "Amber",
     ['chance'] = 5
    }
  breedingTable[153] = {
     ['allele1'] = "Natural",
     ['specialConditions'] = {},
     ['allele2'] = "Prussian",
     ['result'] = "Turquoise",
     ['chance'] = 5
    }
  breedingTable[154] = {
     ['allele1'] = "Maroon",
     ['specialConditions'] = {},
     ['allele2'] = "Prussian",
     ['result'] = "Indigo",
     ['chance'] = 5
    }
  breedingTable[155] = {
     ['allele1'] = "Ebony",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Slate",
     ['chance'] = 5
    }
  breedingTable[156] = {
     ['allele1'] = "Prussian",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Azure",
     ['chance'] = 5
    }
  breedingTable[157] = {
     ['allele1'] = "Maroon",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Lavender",
     ['chance'] = 5
    }
  breedingTable[158] = {
     ['allele1'] = "Natural",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Lime",
     ['chance'] = 5
    }
  breedingTable[159] = {
     ['allele1'] = "Indigo",
     ['specialConditions'] = {},
     ['allele2'] = "Lavender",
     ['result'] = "Fuchsia",
     ['chance'] = 5
    }
  breedingTable[160] = {
     ['allele1'] = "Slate",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Ashen",
     ['chance'] = 5
    }
  breedingTable[161] = {
     ['allele1'] = "Furious",
     ['specialConditions'] = {},
     ['allele2'] = "Excited",
     ['result'] = "Glowering",
     ['chance'] = 5
    }
  breedingTable[162] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {},
     ['allele2'] = "Desolate",
     ['result'] = "Hazardous",
     ['chance'] = 5
    }
  breedingTable[163] = {
     ['allele1'] = "Ender",
     ['specialConditions'] = {},
     ['allele2'] = "Relic",
     ['result'] = "Jaded",
     ['chance'] = 2
    }
  breedingTable[164] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {},
     ['allele2'] = "Excited",
     ['result'] = "Celebratory",
     ['chance'] = 5
    }
  breedingTable[165] = {
     ['allele1'] = "Secluded",
     ['specialConditions'] = {},
     ['allele2'] = "Ender",
     ['result'] = "Abnormal",
     ['chance'] = 5
    }
  breedingTable[166] = {
     ['allele1'] = "Abnormal",
     ['specialConditions'] = {},
     ['allele2'] = "Hermitic",
     ['result'] = "Spatial",
     ['chance'] = 5
    }
  breedingTable[167] = {
     ['allele1'] = "Spatial",
     ['specialConditions'] = {},
     ['allele2'] = "Spectral",
     ['result'] = "Quantum",
     ['chance'] = 5
    }
  breedingTable[168] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[169] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[170] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[171] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[172] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[173] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[174] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[175] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[176] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[177] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[178] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[179] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[180] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[181] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[182] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[183] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[184] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[185] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[186] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[187] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[188] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[189] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[190] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[191] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[192] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[193] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[194] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[195] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[196] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[197] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[198] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[199] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[200] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[201] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[202] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[203] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[204] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[205] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[206] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[207] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[208] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[209] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[210] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[211] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[212] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Esoteric",
     ['chance'] = 10
    }
  breedingTable[213] = {
     ['allele1'] = "Eldritch",
     ['specialConditions'] = {},
     ['allele2'] = "Esoteric",
     ['result'] = "Mysterious",
     ['chance'] = 8
    }
  breedingTable[214] = {
     ['allele1'] = "Esoteric",
     ['specialConditions'] = {},
     ['allele2'] = "Mysterious",
     ['result'] = "Arcane",
     ['chance'] = 8
    }
  breedingTable[215] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Charmed",
     ['chance'] = 10
    }
  breedingTable[216] = {
     ['allele1'] = "Eldritch",
     ['specialConditions'] = {},
     ['allele2'] = "Charmed",
     ['result'] = "Enchanted",
     ['chance'] = 8
    }
  breedingTable[217] = {
     ['allele1'] = "Charmed",
     ['specialConditions'] = {},
     ['allele2'] = "Enchanted",
     ['result'] = "Supernatural",
     ['chance'] = 8
    }
  breedingTable[218] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Supernatural",
     ['result'] = "Ethereal",
     ['chance'] = 7
    }
  breedingTable[219] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Oak Leaves"},
     ['allele2'] = "Ethereal",
     ['result'] = "Windy",
     ['chance'] = 14
    }
  breedingTable[220] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Water"},
     ['allele2'] = "Ethereal",
     ['result'] = "Watery",
     ['chance'] = 14
    }
  breedingTable[221] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Bricks"},
     ['allele2'] = "Ethereal",
     ['result'] = "Earthen",
     ['chance'] = 100
    }
  breedingTable[222] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Lava"},
     ['allele2'] = "Ethereal",
     ['result'] = "Firey",
     ['chance'] = 14
    }
  breedingTable[223] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {},
     ['allele2'] = "Attuned",
     ['result'] = "Aware",
     ['chance'] = 10
    }
  breedingTable[224] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {},
     ['allele2'] = "Aware",
     ['result'] = "Spirit",
     ['chance'] = 8
    }
  breedingTable[225] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Aware",
     ['result'] = "Spirit",
     ['chance'] = 8
    }
  breedingTable[226] = {
     ['allele1'] = "Aware",
     ['specialConditions'] = {},
     ['allele2'] = "Spirit",
     ['result'] = "Soul",
     ['chance'] = 7
    }
  breedingTable[227] = {
     ['allele1'] = "Monastic",
     ['specialConditions'] = {},
     ['allele2'] = "Arcane",
     ['result'] = "Pupil",
     ['chance'] = 10
    }
  breedingTable[228] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Pupil",
     ['result'] = "Scholarly",
     ['chance'] = 8
    }
  breedingTable[229] = {
     ['allele1'] = "Pupil",
     ['specialConditions'] = {},
     ['allele2'] = "Scholarly",
     ['result'] = "Savant",
     ['chance'] = 6
    }
  breedingTable[230] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Timely",
     ['chance'] = 8
    }
  breedingTable[231] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {},
     ['allele2'] = "Timely",
     ['result'] = "Lordly",
     ['chance'] = 8
    }
  breedingTable[232] = {
     ['allele1'] = "Timely",
     ['specialConditions'] = {},
     ['allele2'] = "Lordly",
     ['result'] = "Doctoral",
     ['chance'] = 7
    }
  breedingTable[233] = {
     ['allele1'] = "Infernal",
     ['specialConditions'] = {[1] = "Occurs within a Nether biome"},
     ['allele2'] = "Eldritch",
     ['result'] = "Hateful",
     ['chance'] = 9
    }
  breedingTable[234] = {
     ['allele1'] = "Infernal",
     ['specialConditions'] = {},
     ['allele2'] = "Hateful",
     ['result'] = "Spiteful",
     ['chance'] = 7
    }
  breedingTable[235] = {
     ['allele1'] = "Demonic",
     ['specialConditions'] = {},
     ['allele2'] = "Spiteful",
     ['result'] = "Withering",
     ['chance'] = 6
    }
  breedingTable[236] = {
     ['allele1'] = "Modest",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Skulking",
     ['chance'] = 12
    }
  breedingTable[237] = {
     ['allele1'] = "Tropical",
     ['specialConditions'] = {},
     ['allele2'] = "Skulking",
     ['result'] = "Spidery",
     ['chance'] = 10
    }
  breedingTable[238] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Ghastly",
     ['chance'] = 9
    }
  breedingTable[239] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Hateful",
     ['result'] = "Smouldering",
     ['chance'] = 7
    }
  breedingTable[240] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {},
     ['allele2'] = "Oblivion",
     ['result'] = "Nameless",
     ['chance'] = 10
    }
  breedingTable[241] = {
     ['allele1'] = "Oblivion",
     ['specialConditions'] = {},
     ['allele2'] = "Nameless",
     ['result'] = "Abandoned",
     ['chance'] = 8
    }
  breedingTable[242] = {
     ['allele1'] = "Nameless",
     ['specialConditions'] = {},
     ['allele2'] = "Abandoned",
     ['result'] = "Forlorn",
     ['chance'] = 6
    }
  breedingTable[243] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Occurs within a End biome"},
     ['allele2'] = "Abandoned",
     ['result'] = "Draconic",
     ['chance'] = 6
    }
  breedingTable[244] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Mutable",
     ['chance'] = 12
    }
  breedingTable[245] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Mutable",
     ['result'] = "Transmuting",
     ['chance'] = 9
    }
  breedingTable[246] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Mutable",
     ['result'] = "Crumbling",
     ['chance'] = 9
    }
  breedingTable[247] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Mutable",
     ['result'] = "Invisible",
     ['chance'] = 15
    }
  breedingTable[248] = {
     ['allele1'] = "Industrious",
     ['specialConditions'] = {[1] = "Requires a foundation of Copper Block"},
     ['allele2'] = "Meadows",
     ['result'] = "Cuprum",
     ['chance'] = 12
    }
  breedingTable[249] = {
     ['allele1'] = "Industrious",
     ['specialConditions'] = {[1] = "Requires a foundation of Tin Block"},
     ['allele2'] = "Forest",
     ['result'] = "Stannum",
     ['chance'] = 12
    }
  breedingTable[250] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Iron"},
     ['allele2'] = "Industrious",
     ['result'] = "Ferrous",
     ['chance'] = 12
    }
  breedingTable[251] = {
     ['allele1'] = "Stannum",
     ['specialConditions'] = {[1] = "Requires a foundation of Lead Block"},
     ['allele2'] = "Common",
     ['result'] = "Plumbum",
     ['chance'] = 10
    }
  breedingTable[252] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Silver"},
     ['allele2'] = "Modest",
     ['result'] = "Argentum",
     ['chance'] = 8
    }
  breedingTable[253] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Gold"},
     ['allele2'] = "Plumbum",
     ['result'] = "Auric",
     ['chance'] = 8
    }
  breedingTable[254] = {
     ['allele1'] = "Industrious",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Ardite"},
     ['allele2'] = "Infernal",
     ['result'] = "Ardite",
     ['chance'] = 9
    }
  breedingTable[255] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Cobalt"},
     ['allele2'] = "Infernal",
     ['result'] = "Cobalt",
     ['chance'] = 9
    }
  breedingTable[256] = {
     ['allele1'] = "Ardite",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Manyullyn"},
     ['allele2'] = "Cobalt",
     ['result'] = "Manyullyn",
     ['chance'] = 9
    }
  breedingTable[257] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Diamond"},
     ['allele2'] = "Auric",
     ['result'] = "Diamandi",
     ['chance'] = 7
    }
  breedingTable[258] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Emerald"},
     ['allele2'] = "Argentum",
     ['result'] = "Esmeraldi",
     ['chance'] = 6
    }
  breedingTable[259] = {
     ['allele1'] = "Rural",
     ['specialConditions'] = {[1] = "Requires a foundation of Apatite Ore"},
     ['allele2'] = "Cuprum",
     ['result'] = "Apatine",
     ['chance'] = 12
    }
  breedingTable[260] = {
     ['allele1'] = "Windy",
     ['specialConditions'] = {[1] = "Requires a foundation of Air Crystal Cluster"},
     ['allele2'] = "Windy",
     ['result'] = "Aer",
     ['chance'] = 8
    }
  breedingTable[261] = {
     ['allele1'] = "Firey",
     ['specialConditions'] = {[1] = "Requires a foundation of Fire Crystal Cluster"},
     ['allele2'] = "Firey",
     ['result'] = "Ignis",
     ['chance'] = 8
    }
  breedingTable[262] = {
     ['allele1'] = "Watery",
     ['specialConditions'] = {[1] = "Requires a foundation of Water Crystal Cluster"},
     ['allele2'] = "Watery",
     ['result'] = "Aqua",
     ['chance'] = 8
    }
  breedingTable[263] = {
     ['allele1'] = "Earthen",
     ['specialConditions'] = {[1] = "Requires a foundation of Earth Crystal Cluster"},
     ['allele2'] = "Earthen",
     ['result'] = "Solum",
     ['chance'] = 8
    }
  breedingTable[264] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {[1] = "Requires a foundation of Order Crystal Cluster"},
     ['allele2'] = "Arcane",
     ['result'] = "Ordered",
     ['chance'] = 8
    }
  breedingTable[265] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {[1] = "Requires a foundation of Entropy Crystal Cluster"},
     ['allele2'] = "Supernatural",
     ['result'] = "Chaotic",
     ['chance'] = 8
    }
  breedingTable[266] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Windy",
     ['result'] = "Batty",
     ['chance'] = 9
    }
  breedingTable[267] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Pupil",
     ['result'] = "Brainy",
     ['chance'] = 9
    }
  breedingTable[268] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Occurs within a Forest biome"},
     ['allele2'] = "Skulking",
     ['result'] = "Poultry",
     ['chance'] = 12
    }
  breedingTable[269] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Occurs within a Plains biome"},
     ['allele2'] = "Skulking",
     ['result'] = "Beefy",
     ['chance'] = 12
    }
  breedingTable[270] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Occurs within a Mountain biome"},
     ['allele2'] = "Skulking",
     ['result'] = "Porcine",
     ['chance'] = 12
    }
  breedingTable[271] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Essence",
     ['chance'] = 10
    }
  breedingTable[272] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Essence",
     ['result'] = "Quintessential",
     ['chance'] = 7
    }
  breedingTable[273] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Windy",
     ['result'] = "Luft",
     ['chance'] = 10
    }
  breedingTable[274] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Earthen",
     ['result'] = "Erde",
     ['chance'] = 10
    }
  breedingTable[275] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Firey",
     ['result'] = "Feuer",
     ['chance'] = 10
    }
  breedingTable[276] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Watery",
     ['result'] = "Wasser",
     ['chance'] = 10
    }
  breedingTable[277] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Arkanen",
     ['chance'] = 10
    }
  breedingTable[278] = {
     ['allele1'] = "Windy",
     ['specialConditions'] = {},
     ['allele2'] = "Luft",
     ['result'] = "Blitz",
     ['chance'] = 8
    }
  breedingTable[279] = {
     ['allele1'] = "Earthen",
     ['specialConditions'] = {},
     ['allele2'] = "Erde",
     ['result'] = "Staude",
     ['chance'] = 8
    }
  breedingTable[280] = {
     ['allele1'] = "Watery",
     ['specialConditions'] = {},
     ['allele2'] = "Wasser",
     ['result'] = "Eis",
     ['chance'] = 8
    }
  breedingTable[281] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Essence",
     ['result'] = "Vortex",
     ['chance'] = 8
    }
  breedingTable[282] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Ghastly",
     ['result'] = "Wight",
     ['chance'] = 8
    }
  breedingTable[283] = {
     ['allele1'] = "Stannum",
     ['specialConditions'] = {[1] = "Requires a foundation of Bronze Block"},
     ['allele2'] = "Cuprum",
     ['result'] = "Tinker",
     ['chance'] = 12
    }
  breedingTable[284] = {
     ['allele1'] = "Auric",
     ['specialConditions'] = {[1] = "Requires a foundation of Electrum Block"},
     ['allele2'] = "Argentum",
     ['result'] = "Electrum",
     ['chance'] = 10
    }
  breedingTable[285] = {
     ['allele1'] = "Ferrous",
     ['specialConditions'] = {[1] = "Requires a foundation of Ferrous Block"},
     ['allele2'] = "Esoteric",
     ['result'] = "Nickel",
     ['chance'] = 14
    }
  breedingTable[286] = {
     ['allele1'] = "Ferrous",
     ['specialConditions'] = {[1] = "Requires a foundation of Invar Block"},
     ['allele2'] = "Nickel",
     ['result'] = "Invar",
     ['chance'] = 14
    }
  breedingTable[287] = {
     ['allele1'] = "Nickel",
     ['specialConditions'] = {[1] = "Requires a foundation of Shiny Block"},
     ['allele2'] = "Invar",
     ['result'] = "Platinum",
     ['chance'] = 10
    }
  breedingTable[288] = {
     ['allele1'] = "Spiteful",
     ['specialConditions'] = {[1] = "Requires a foundation of Coal Ore"},
     ['allele2'] = "Stannum",
     ['result'] = "Carbon",
     ['chance'] = 12
    }
  breedingTable[289] = {
     ['allele1'] = "Spiteful",
     ['specialConditions'] = {[1] = "Requires a foundation of Redstone Ore"},
     ['allele2'] = "Industrious",
     ['result'] = "Destabilized",
     ['chance'] = 12
    }
  breedingTable[290] = {
     ['allele1'] = "Smouldering",
     ['specialConditions'] = {[1] = "Requires a foundation of Glowstone"},
     ['allele2'] = "Infernal",
     ['result'] = "Lux",
     ['chance'] = 12
    }
  breedingTable[291] = {
     ['allele1'] = "Smouldering",
     ['specialConditions'] = {},
     ['allele2'] = "Austere",
     ['result'] = "Dante",
     ['chance'] = 12
    }
  breedingTable[292] = {
     ['allele1'] = "Dante",
     ['specialConditions'] = {},
     ['allele2'] = "Carbon",
     ['result'] = "Pyro",
     ['chance'] = 8
    }
  breedingTable[293] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Blizzy",
     ['chance'] = 12
    }
  breedingTable[294] = {
     ['allele1'] = "Blizzy",
     ['specialConditions'] = {},
     ['allele2'] = "Icy",
     ['result'] = "Gelid",
     ['chance'] = 8
    }
  breedingTable[295] = {
     ['allele1'] = "Platinum",
     ['specialConditions'] = {},
     ['allele2'] = "Oblivion",
     ['result'] = "Winsome",
     ['chance'] = 12
    }
  breedingTable[296] = {
     ['allele1'] = "Winsome",
     ['specialConditions'] = {[1] = "Requires a foundation of Enderium Block"},
     ['allele2'] = "Carbon",
     ['result'] = "Endearing",
     ['chance'] = 8
    }
  breedingTable[297] = {
     ['allele1'] = "Windy",
     ['specialConditions'] = {[1] = "Requires a foundation of Skystone"},
     ['allele2'] = "Earthen",
     ['result'] = "Skystone",
     ['chance'] = 20
    }
  breedingTable[298] = {
     ['allele1'] = "Skystone",
     ['specialConditions'] = {},
     ['allele2'] = "Ferrous",
     ['result'] = "Silicon",
     ['chance'] = 17
    }
  breedingTable[299] = {
     ['allele1'] = "Silicon",
     ['specialConditions'] = {},
     ['allele2'] = "Energetic",
     ['result'] = "Infinity",
     ['chance'] = 20
    }
  return breedingTable
end


-- build mutation graph
function buildMutationGraph(apiary)
  local mutations = {}
  local beeNames = {}
  function addMutateTo(parent1, parent2, offspring, chance)
    beeNames[parent1] = true
    beeNames[parent2] = true
    beeNames[offspring] = true
    if mutations[parent1] ~= nil then
      if mutations[parent1].mutateTo[offspring] ~= nil then
        mutations[parent1].mutateTo[offspring][parent2] = chance
      else
        mutations[parent1].mutateTo[offspring] = {[parent2] = chance}
      end
    else
      mutations[parent1] = {
        mutateTo = {[offspring]={[parent2] = chance}}
      }
    end
  end
  for _, parents in pairs(getBeeBreedingData()) do
    fixParents(parents)
    addMutateTo(parents.allele1, parents.allele2, parents.result, parents.chance)
    addMutateTo(parents.allele2, parents.allele1, parents.result, parents.chance)
  end
  --mutations.getBeeParents = function(name)
    --return apiary.getBeeParents((nameFix[name] or name))
  --end
  return mutations, beeNames
end

function buildTargetSpeciesList(catalog, apiary)
  local targetSpeciesList = {}
  local parentss = getBeeBreedingData()
  for _, parents in pairs(parentss) do
    local skip = false
    for i, ignoreSpecies in ipairs(config.ignoreSpecies) do
      if parents.result == ignoreSpecies then
        skip = true
        break
      end
    end
    if not skip and
        ( -- skip if reference pair exists
          catalog.referencePrincessesBySpecies[parents.result] == nil or
          catalog.referenceDronesBySpecies[parents.result] == nil
        ) and
        ( -- princess 1 and drone 2 available
          catalog.princessesBySpecies[parents.allele1] ~= nil and
          catalog.dronesBySpecies[parents.allele2] ~= nil
        ) or
        ( -- princess 2 and drone 1 available
          catalog.princessesBySpecies[parents.allele2] ~= nil and
          catalog.dronesBySpecies[parents.allele1] ~= nil
        ) then
      table.insert(targetSpeciesList, parents.result)
    end
  end
  return targetSpeciesList
end

-- percent chance of 2 species turning into a target species
function mutateSpeciesChance(mutations, species1, species2, targetSpecies)
  local chance = {}
  if species1 == species2 then
    chance[species1] = 100
  else
    chance[species1] = 50
    chance[species2] = 50
  end
  if mutations[species1] ~= nil then
    for species, mutates in pairs(mutations[species1].mutateTo) do
      local mutateChance = mutates[species2]
      if mutateChance ~= nil then
        chance[species] = mutateChance
        chance[species1] = chance[species1] - mutateChance / 2
        chance[species2] = chance[species2] - mutateChance / 2
      end
    end
  end
  return chance[targetSpecies] or 0.0
end

-- percent chance of 2 bees turning into target species
function mutateBeeChance(mutations, princess, drone, targetSpecies)
  if princess.individual.isAnalyzed then
    if drone.individual.isAnalyzed then
      return (mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.active.species.name, targetSpecies) / 4
             +mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.active.species.name, targetSpecies) / 4
             +mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.inactive.species.name, targetSpecies) / 4
             +mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.inactive.species.name, targetSpecies) / 4)
    end
  elseif drone.individual.isAnalyzed then
  else
    return mutateSpeciesChance(princess.individual.displayName, drone.individual.displayName, targetSpecies)
  end
end

function buildScoring()
  function makeNumberScorer(trait, default)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return (bee.individual.active[trait] + bee.individual.inactive[trait]) / 2
      else
        return default
      end
    end
    return scorer
  end

  function makeBooleanScorer(trait)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active[trait] and 1 or 0) + (bee.individual.inactive[trait] and 1 or 0)) / 2
      else
        return 0
      end
    end
    return scorer
  end

  function makeTableScorer(trait, default, lookup)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((lookup[bee.individual.active[trait]] or default) + (lookup[bee.individual.inactive[trait]] or default)) / 2
      else
        return default
      end
    end
    return scorer
  end

  local scoresTolerance = {
    ["None"]   = 0,
    ["Up 1"]   = 1,
    ["Up 2"]   = 2,
    ["Up 3"]   = 3,
    ["Up 4"]   = 4,
    ["Up 5"]   = 5,
    ["Down 1"] = 1,
    ["Down 2"] = 2,
    ["Down 3"] = 3,
    ["Down 4"] = 4,
    ["Down 5"] = 5,
    ["Both 1"] = 2,
    ["Both 2"] = 4,
    ["Both 3"] = 6,
    ["Both 4"] = 8,
    ["Both 5"] = 10
  }

  local scoresFlowerProvider = {
    ["None"] = 5,
    ["Rocks"] = 4,
    ["Flowers"] = 3,
    ["Mushroom"] = 2,
    ["Cacti"] = 1,
    ["Exotic Flowers"] = 0,
    ["Jungle"] = 0,
    ["Snow"] = 0,
    ["Lily Pads"] = 0
  }

  return {
    ["fertility"] = makeNumberScorer("fertility", 1),
    ["flowering"] = makeNumberScorer("flowering", 1),
    ["speed"] = makeNumberScorer("speed", 1),
    ["lifespan"] = makeNumberScorer("lifespan", 1),
    ["nocturnal"] = makeBooleanScorer("nocturnal"),
    ["tolerantFlyer"] = makeBooleanScorer("tolerantFlyer"),
    ["caveDwelling"] = makeBooleanScorer("caveDwelling"),
    ["effect"] = makeBooleanScorer("effect"),
    ["temperatureTolerance"] = makeTableScorer("temperatureTolerance", 0, scoresTolerance),
    ["humidityTolerance"] = makeTableScorer("humidityTolerance", 0, scoresTolerance),
    ["flowerProvider"] = makeTableScorer("flowerProvider", 0, scoresFlowerProvider),
    ["territory"] = function(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active.territory[1] * bee.individual.active.territory[2] * bee.individual.active.territory[3]) +
                     (bee.individual.inactive.territory[1] * bee.individual.inactive.territory[2] * bee.individual.inactive.territory[3])) / 2
      else
        return 0
      end
    end
  }
end

function compareBees(scorers, a, b)
  for _, trait in ipairs(traitPriority) do
    local scorer = scorers[trait]
    if scorer ~= nil then
      local aScore = scorer(a)
      local bScore = scorer(b)
      if aScore ~= bScore then
        return aScore > bScore
      end
    end
  end
  return true
end

function compareMates(a, b)
  for i, trait in ipairs(traitPriority) do
    if a[trait] ~= b[trait] then
      return a[trait] > b[trait]
    end
  end
  return true
end

function betterTraits(scorers, a, b)
  local traits = {}
  for _, trait in ipairs(traitPriority) do
    local scorer = scorers[trait]
    if scorer ~= nil then
      local aScore = scorer(a)
      local bScore = scorer(b)
      if bScore > aScore then
        table.insert(traits, trait)
      end
    end
  end
  return traits
end

-- cataloging functions ---------------

function addBySpecies(beesBySpecies, bee)
  if bee.individual.isAnalyzed then
    if beesBySpecies[bee.individual.active.species.name] == nil then
      beesBySpecies[bee.individual.active.species.name] = {bee}
    else
      table.insert(beesBySpecies[bee.individual.active.species.name], bee)
    end
    if bee.individual.inactive.species.name ~= bee.individual.active.species.name then
      if beesBySpecies[bee.individual.inactive.species.name] == nil then
        beesBySpecies[bee.individual.inactive.species.name] = {bee}
      else
        table.insert(beesBySpecies[bee.individual.inactive.species.name], bee)
      end
    end
  else
    if beesBySpecies[bee.individual.displayName] == nil then
      beesBySpecies[bee.individual.displayName] = {bee}
    else
      table.insert(beesBySpecies[bee.individual.displayName], bee)
    end
  end
end

function catalogBees(inv, scorers)
  catalog = {}
  catalog.princesses = {}
  catalog.princessesBySpecies = {}
  catalog.drones = {}
  catalog.dronesBySpecies = {}
  catalog.queens = {}
  catalog.referenceDronesBySpecies = {}
  catalog.referencePrincessesBySpecies = {}
  catalog.referencePairBySpecies = {}

  -- phase 0 -- analyze bees and ditch product
  inv.condenseItems()
  if detailedOutput then
    logLine(alwaysShow, string.format("Scanning %d slots for new bees.", inv.size))
  else
    logLine(alwaysShow, "Scanning bee chest for changes & analyzing new bees.")
  end
  if useAnalyzer == true then
    local analyzeCount = 0
    local bees = getAllBees(inv)
    for slot, bee in pairs(bees) do
      if bee.individual == nil then
        inv.pushItem(config.chestDir, slot)
      elseif not bee.individual.isAnalyzed then
        analyzeBee(inv, slot)
        analyzeCount = analyzeCount + 1
      end
    end
	log("Analyzed ")
	log(string.format("%d", analyzeCount), config.targetColor)
	log(" new bees. \n")
  end
  -- phase 1 -- mark reference bees
  inv.condenseItems()
  local referenceBeeCount = 0
  local referenceDroneCount = 0
  local referencePrincessCount = 0
  local isDrone = nil
  local bees = getAllBees(inv)
  if useReferenceBees then
    for slot = 1, #bees do
      local bee = bees[slot]
      if bee.individual ~= nil then
        fixBee(bee)
        local referenceBySpecies = nil
        if bee.raw_name == "item.for.beedronege" then -- drones
          isDrone = true
          referenceBySpecies = catalog.referenceDronesBySpecies
        elseif bee.raw_name == "item.for.beeprincessge" then -- princess
          isDrone = false
          referenceBySpecies = catalog.referencePrincessesBySpecies
        else
          isDrone = nil
        end
        if referenceBySpecies ~= nil and bee.individual.isAnalyzed and bee.individual.active.species.name == bee.individual.inactive.species.name then
          local species = bee.individual.active.species.name
          if referenceBySpecies[species] == nil or
              compareBees(scorers, bee, referenceBySpecies[species]) then
            if referenceBySpecies[species] == nil then
              referenceBeeCount = referenceBeeCount + 1
              if isDrone == true then
                referenceDroneCount = referenceDroneCount + 1
              elseif isDrone == false then
                referencePrincessCount = referencePrincessCount + 1
              end
              if slot ~= referenceBeeCount then
                inv.swapStacks(slot, referenceBeeCount)
              end
              bee.slot = referenceBeeCount
            else
              inv.swapStacks(slot, referenceBySpecies[species].slot)
              bee.slot = referenceBySpecies[species].slot
            end
            referenceBySpecies[species] = bee
            if catalog.referencePrincessesBySpecies[species] ~= nil and catalog.referenceDronesBySpecies[species] ~= nil then
              catalog.referencePairBySpecies[species] = true
            end
          end
        end
      end
    end
    logLine(config.detailedOutput, string.format("Found %d reference bees, %d princesses, %d drones", referenceBeeCount, referencePrincessCount, referenceDroneCount))
    if config.detailedOutput then
		log("reference pairs")
		for species, _ in pairs(catalog.referencePairBySpecies) do
		  log(", ")
		  log(species)
		end
		logLine(alwaysShow)
	end
  end
  -- phase 2 -- ditch obsolete drones
  bees = getAllBees(inv)
  local extraDronesBySpecies = {}
  local ditchSlot = 1
  for slot = 1 + referenceBeeCount, #bees do
    local bee = bees[slot]
    fixBee(bee)
    bee.slot = slot
    -- remove analyzed drones where both the active and inactive species have
    --   a both reference princess and drone
    if (
      bee.raw_name == "item.for.beedronege" and
      bee.individual.isAnalyzed and (
        catalog.referencePrincessesBySpecies[bee.individual.active.species.name] ~= nil and
        catalog.referenceDronesBySpecies[bee.individual.active.species.name] ~= nil and
        catalog.referencePrincessesBySpecies[bee.individual.inactive.species.name] ~= nil and
        catalog.referenceDronesBySpecies[bee.individual.inactive.species.name] ~= nil
      )
    ) then
      local activeDroneTraits = betterTraits(scorers, catalog.referenceDronesBySpecies[bee.individual.active.species.name], bee)
      local inactiveDroneTraits = betterTraits(scorers, catalog.referenceDronesBySpecies[bee.individual.inactive.species.name], bee)
      if #activeDroneTraits > 0 or #inactiveDroneTraits > 0 then
        -- keep current bee because it has some trait that is better
        -- manipulate reference bee to have better yet less important attribute
        -- this ditches more bees while keeping at least one with the attribute
        -- the cataloging step will fix the manipulation
        for i, trait in ipairs(activeDroneTraits) do
          catalog.referenceDronesBySpecies[bee.individual.active.species.name].individual.active[trait] = bee.individual.active[trait]
          catalog.referenceDronesBySpecies[bee.individual.active.species.name].individual.inactive[trait] = bee.individual.inactive[trait]
        end
        for i, trait in ipairs(inactiveDroneTraits) do
          catalog.referenceDronesBySpecies[bee.individual.inactive.species.name].individual.active[trait] = bee.individual.active[trait]
          catalog.referenceDronesBySpecies[bee.individual.inactive.species.name].individual.inactive[trait] = bee.individual.inactive[trait]
        end
      else
        -- keep 1 extra drone around if purebreed
        -- this speeds up breeding by not ditching drones you just breed from reference bees
        -- when the reference bee drone output is still mutating
        local ditchDrone = nil
        if bee.individual.active.species.name == bee.individual.inactive.species.name then
          if extraDronesBySpecies[bee.individual.active.species.name] == nil then
            extraDronesBySpecies[bee.individual.active.species.name] = bee
            bee = nil
          elseif compareBees(bee, extraDronesBySpecies[bee.individual.active.species.name]) then
            ditchDrone = extraDronesBySpecies[bee.individual.active.species.name]
            extraDronesBySpecies[bee.individual.active.species.name] = bee
            bee = ditchDrone
          end
        end
        -- ditch drone
        if bee ~= nil then
          if inv.pushItem(config.chestDir, bee.slot) == 0 then
            error("Ditch chest is full")
          end
        end
      end
    end
  end
  -- phase 3 -- catalog bees
  bees = getAllBees(inv)
  for slot, bee in pairs(bees) do
    fixBee(bee)
    bee.slot = slot
    if slot > referenceBeeCount then
      if bee.raw_name == "item.for.beedronege" then -- drones
        table.insert(catalog.drones, bee)
        addBySpecies(catalog.dronesBySpecies, bee)
      elseif bee.raw_name == "item.for.beeprincessge" then -- princess
        table.insert(catalog.princesses, bee)
        addBySpecies(catalog.princessesBySpecies, bee)
      elseif bee.id == 13339 then -- queens
        table.insert(catalog.queens, bee)
      end
    else
      if bee.raw_name == "item.for.beedronege" and bee.qty > 1 then
        table.insert(catalog.drones, bee)
        addBySpecies(catalog.dronesBySpecies, bee)
      end
    end
  end
  logLine(config.detailedOutput, string.format("Found %d queens, %d princesses, %d drones",
      #catalog.queens, #catalog.princesses, #catalog.drones))
  return catalog
end

-- interaction functions --------------

function clearApiary(inv, apiary)
  local bees = getAllBees(apiary)
  local counter = 0
  -- wait for queen to die
  if (bees[1] ~= nil and bees[1].raw_name == "item.for.beequeenge")
      or (bees[1] ~= nil and bees[2] ~= nil) then
    log("Waiting for apiary")
    while true do
      sleep(5)
      bees = getAllBees(apiary)
      if bees[1] == nil then
        break
      end
	  
	  -- if detailed, log every check. Otherwise, log every logSkipth
	  if config.detailedOutput then
		log(".")
	  else
	    counter = counter + 1
	    if counter % logSkip == logSkip - 1 then
		  log(".")
		end
	  end
    end
    logLine(alwaysShow, "Done!")
  end

  local minSlot = 3
  local maxSlot = 9
  
  if config.apiaryType == "industrial" then
    minSlot = 7
    maxSlot = 15
  end

  for slot = minSlot, maxSlot do
    local bee = bees[slot]
    if bee ~= nil then
      if bee.raw_name == "item.for.beedronege" or bee.raw_name == "item.for.beeprincessge" then
        apiary.pushItem(config.chestDir, slot, 64)
      else
        apiary.pushItem(config.productDir, slot, 64)
      end
    end
  end
end

function clearAnalyzer(inv)
  if not useAnalyzer then
    return
  end
  local bees = getAllBees(inv)
  if #bees == inv.size then
    error("chest is full")
  end
  for analyzerSlot = 9, 12 do
    if inv.pullItem(config.analyzerDir, analyzerSlot) == 0 then
      break
    end
  end
end

function analyzeBee(inv, slot)
  clearAnalyzer(inv)
  if config.detailedOutput then
	  log("Analyzing bee ")
	  log(slot)
	  log("...\n")
  end
  local freeSlot
  if inv.pushItem(config.analyzerDir, slot, 64, 3) > 0 then
    while true do
      -- constantly check in case of inventory manipulation by player
      local bees = getAllBees(inv)
      freeSlot = nil
      for i = 1, inv.size do
        if bees[i] == nil then
          freeSlot = i
          break
        end
      end
      if inv.pullItem(config.analyzerDir, 9) > 0 then
        break
      end
      sleep(1)
    end
  else
    logLine(alwaysShow, "Missing Analyzer")
    useAnalyzer = false
    return nil
  end
  if detailedOutput then
  local bee = getBeeInSlot(inv, freeSlot)
	  if bee ~= nil then
		printBee(fixBee(bee))
	  end
  end
  return freeSlot
end

function log_r ( t )  
    local print_r_cache={}
    local function sub_print_r(t,indent)
        if (print_r_cache[tostring(t)]) then
            logLine(indent.."*"..tostring(t))
        else
            print_r_cache[tostring(t)]=true
            if (type(t)=="table") then
                for pos,val in pairs(t) do
                    if (type(val)=="table") then
                        logLine(indent.."["..pos.."] => "..tostring(t).." {")
                        sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                        logLine(indent..string.rep(" ",string.len(pos)+6).."}")
                    elseif (type(val)=="string") then
                        logLine(indent.."["..pos..'] => "'..val..'"')
                    else
                        logLine(indent.."["..pos.."] => "..tostring(val))
                    end
                end
            else
                logLine(indent..tostring(t))
            end
        end
    end
    if (type(t)=="table") then
        logLine(tostring(t).." {")
        sub_print_r(t,"  ")
        logLine("}")
    else
        sub_print_r(t,"  ")
    end
    logLine()
end

function breedBees(inv, apiary, princess, drone)
  clearApiary(inv, apiary)
  apiary.pullItem(config.chestDir, princess.slot, 1, 1)
  apiary.pullItem(config.chestDir, drone.slot, 1, 2)
  clearApiary(inv, apiary)
end

-- Breeds any queens left in the bee chest
function breedQueen(inv, apiary, queen)
  log("Queen found in chest, sending her to apiary.")
  clearApiary(inv, apiary)
  apiary.pullItem(config.chestDir, queen.slot, 1, 1)
  clearApiary(inv, apiary)
end

-- selects best pair for target species
--   or initiates breeding of lower species

function getBeeParents(targetSpecies)
  for _, bee in pairs(getBeeBreedingData()) do
    if bee.result == targetSpecies then
      return bee
    end
  end
end

function selectPair(mutations, scorers, catalog, targetSpecies)
  log("Targeting ")
  log(string.format("%s\n", targetSpecies), config.targetColor)
  local baseChance = 0
  if #getBeeParents(targetSpecies) > 0 then
    local parents = getBeeParents(targetSpecies)[1]
    baseChance = parents.chance
    for _, s in ipairs(parents.specialConditions) do
      logLine(alwaysShow, "    ", s)
    end
  end
  local mateCombos = choose(catalog.princesses, catalog.drones)
  local mates = {}
  local haveReference = (catalog.referencePrincessesBySpecies[targetSpecies] ~= nil and
      catalog.referenceDronesBySpecies[targetSpecies] ~= nil)
  for i, v in ipairs(mateCombos) do
    local chance = mutateBeeChance(mutations, v[1], v[2], targetSpecies) or 0
    if (not haveReference and chance >= baseChance / 2) or
        (haveReference and chance > 25) then
      local newMates = {
        ["princess"] = v[1],
        ["drone"] = v[2],
        ["speciesChance"] = chance
      }
      for trait, scorer in pairs(scorers) do
        newMates[trait] = (scorer(v[1]) + scorer(v[2])) / 2
      end
      table.insert(mates, newMates)
    end
  end
  if #mates > 0 then
    table.sort(mates, compareMates)
    for i = math.min(#mates, 10), 1, -1 do
      local parents = mates[i]
	  logLine(config.detailedOutput, beeName(parents.princess), " ", beeName(parents.drone), " ", parents.speciesChance, " ", parents.fertility, " ",
			parents.flowering, " ", parents.nocturnal, " ", parents.tolerantFlyer, " ", parents.caveDwelling, " ",
			parents.lifespan, " ", parents.temperatureTolerance, " ", parents.humidityTolerance)
    end
    return mates[1]
  else
    -- check for reference bees and breed if drone count is 1
    if catalog.referencePrincessesBySpecies[targetSpecies] ~= nil and
        catalog.referenceDronesBySpecies[targetSpecies] ~= nil then
      logLine(alwaysShow, "Breeding extra drone from reference bees")
      return {
        ["princess"] = catalog.referencePrincessesBySpecies[targetSpecies],
        ["drone"] = catalog.referenceDronesBySpecies[targetSpecies]
      }
    end
    -- attempt lower tier bee
    local parentss = getBeeParents(targetSpecies)
    if #parentss > 0 then
      logLine(alwaysShow, "Mutation impossible, trying next lower tier.")
      --print(textutils.serialize(catalog.referencePrincessesBySpecies))
      table.sort(parentss, function(a, b) return a.chance > b.chance end)
      local trySpecies = {}
      for i, parents in ipairs(parentss) do
        fixParents(parents)
        if (catalog.referencePairBySpecies[parents.allele2] == nil        -- no reference bee pair
            or catalog.referenceDronesBySpecies[parents.allele2].qty <= 1 -- no extra reference drone
            or catalog.princessesBySpecies[parents.allele2] == nil)       -- no converted princess
            and trySpecies[parents.allele2] == nil then
          table.insert(trySpecies, parents.allele2)
          trySpecies[parents.allele2] = true
        end
        if (catalog.referencePairBySpecies[parents.allele1] == nil
            or catalog.referenceDronesBySpecies[parents.allele1].qty <= 1
            or catalog.princessesBySpecies[parents.allele1] == nil)
            and trySpecies[parents.allele1] == nil then
          table.insert(trySpecies, parents.allele1)
          trySpecies[parents.allele1] = true
        end
      end
      for _, species in ipairs(trySpecies) do
        local mates = selectPair(mutations, scorers, catalog, species)
        if mates ~= nil then
          return mates
        end
      end
    end
    return nil
  end
end

function isPureBred(bee1, bee2, targetSpecies)
  if bee1.individual.isAnalyzed and bee2.individual.isAnalyzed then
    if bee1.individual.active.species.name == bee1.individual.inactive.species.name and
        bee2.individual.active.species.name == bee2.individual.inactive.species.name and
        bee1.individual.active.species.name == bee2.individual.active.species.name and
        (targetSpecies == nil or bee1.individual.active.species.name == targetSpecies) then
      return true
    end
  elseif bee1.individual.isAnalyzed == false and bee2.individual.isAnalyzed == false then
    if bee1.individual.displayName == bee2.individual.displayName then
      return true
    end
  end
  return false
end

function breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
  local catalog = catalogBees(inv, scorers)
  while true do
    if #catalog.princesses == 0 then
      logLineColor(config.warningColor, defaultBack, alwaysShow, "Please add more princesses and press [Enter]")
      io.read("*l")
      catalog = catalogBees(inv, scorers)
    elseif #catalog.drones == 0 and next(catalog.referenceDronesBySpecies) == nil then
      logLineColor(config.warningColor, defaultBack, alwaysShow, "Please add more drones and press [Enter]")
      io.read("*l")
      catalog = catalogBees(inv, scorers)
    else
      local mates = selectPair(mutations, scorers, catalog, targetSpecies)
      if mates ~= nil then
        if isPureBred(mates.princess, mates.drone, targetSpecies) then
          break
        else
          breedBees(inv, apiary, mates.princess, mates.drone)
          catalog = catalogBees(inv, scorers)
        end
      else
        logLineColor(config.warningColor, defaultBack, alwaysShow, string.format("Please add more bee species for %s and press [Enter]"), targetSpecies)
        io.read("*l")
        catalog = catalogBees(inv, scorers)
      end
    end
  end
  logLine(alwaysShow, "Bees are purebred")
end

function breedAllSpecies(mutations, inv, apiary, scorers, speciesList)
  if #speciesList == 0 then
    logLineColor(config.warningColor, defaultBack, alwaysShow,"Please add more bee species and press [Enter]")
    io.read("*l")
  else
    for i, targetSpecies in ipairs(speciesList) do
      breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
    end
  end
end

function main(tArgs)
  logLine(alwaysShow, string.format("openbee v%d.%d.%d", version.major, version.minor, version.patch))
  local targetSpecies = setPriorities(tArgs)
  if targetSpecies ~= nil then
    log("Given target species: ")
	log(string.format("%s\n", targetSpecies), config.targetColor)
  else
    logLine(alwaysShow, "No target given, starting general breeding.")
  end
  if detailedOutput then
	log("priority:")
	for _, priority in ipairs(traitPriority) do
		log(" "..priority)
	end
  end
  logLine(alwaysShow, "")
  local inv, apiary = getPeripherals()
  inv.size = inv.getInventorySize()
  local mutations, beeNames = buildMutationGraph(apiary)
  local scorers = buildScoring()
  clearApiary(inv, apiary)
  clearAnalyzer(inv)
  local catalog = catalogBees(inv, scorers)
  while #catalog.queens > 0 do
    breedQueen(inv, apiary, catalog.queens[1])
    catalog = catalogBees(inv, scorers)
  end
  if targetSpecies ~= nil then
    targetSpecies = tArgs[1]:sub(1,1):upper()..tArgs[1]:sub(2):lower()
    if beeNames[targetSpecies] == true then
      breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
    else
      logLineColor(config.warningColor, defaultBack, alwaysShow, string.format("Species '%s' not found.", targetSpecies))
    end
  else
    while true do
      breedAllSpecies(mutations, inv, apiary, scorers, buildTargetSpeciesList(catalog, apiary))
      catalog = catalogBees(inv, scorers)
    end
  end
end

local logFileName = setupLog()
if config.monitor ~= nil then
	local monitor = peripheral.wrap(config.monitor)
	term.redirect(monitor)
end
term.setTextColor(defaultText)
term.setBackgroundColor(defaultBack)
term.clear()
local status, err = pcall(main, {...})
if not status then
  logLine(alwaysShow, err)
end
print("Log file is "..logFileName)
