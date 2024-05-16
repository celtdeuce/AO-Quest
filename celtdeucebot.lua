-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}


colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}


function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
-- Function to assess the threat level of an opponent based on their stats
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function assessThreatLevel(opponentState)
  -- Initialize the threat level
  local threatLevel = 0

  -- Factor in the opponent's health and energy
  local healthWeight = 0.7
  local energyWeight = 0.3
  threatLevel = threatLevel + (opponentState.health * healthWeight) + (opponentState.energy * energyWeight)

  -- Return the calculated threat level
  return threatLevel
end
-- Define the map of possible directions and their corresponding vector changes
local directionMap = {
  Up = {x = 0, y = -1},
  Down = {x = 0, y = 1},
  Left = {x = -1, y = 0},
  Right = {x = 1, y = 0},
  UpRight = {x = 1, y = -1},
  UpLeft = {x = -1, y = -1},
  DownRight = {x = 1, y = 1},
  DownLeft = {x = -1, y = 1}
}

-- Function to decide the next action based on player proximity, energy, and threat level
function gameModeBegins()
  local playerState = LatestGameState.Players[BotID]
  local highestThreatTarget = nil
  local highestThreatLevel = -1

  -- Evaluate the threat level of each opponent within range
  for target, state in pairs(LatestGameState.Players) do
    if target ~= BotID then
      local threatLevel = assessThreatLevel(state)
      if threatLevel > highestThreatLevel and inRange(playerState.x, playerState.y, state.x, state.y, Range) then
        highestThreatLevel = threatLevel
        highestThreatTarget = target
      end
    end
  end

  -- If a high-threat target is in range and the player has enough energy, attack
  if playerState.energy > playerState.attackThreshold and highestThreatTarget then
    performAttack(highestThreatTarget)
  else
    -- If no high-threat target is in range or energy is insufficient, move strategically
    local safeDirection = findSafestDirection(playerState)
    performMove(safeDirection)
  end
  InAction = false
end

-- Function to perform an attack on a target
function performAttack(targetID)
  -- Send a command to the game server to attack the specified target
  ao.send({Target = Game, Action = "PlayerAttack", TargetID = targetID, AttackEnergy = tostring(playerState.attackEnergy)})
end

-- Function to perform a move in a specified direction
function performMove(direction)
  -- Send a command to the game server to move the bot in the specified direction
  ao.send({Target = Game, Action = "PlayerMove", Direction = direction})
end

-- Function to find the safest direction based on the current game state
function findSafestDirection(playerState)
  local safestDirection = "Up"
  local leastDangerousScore = math.huge
-- Function to determine if a given position is dangerous based on the positions of other players
function isPositionDangerous(x, y)
  local dangerZoneRange = 3 -- Define the range within which other players are considered a threat

  for _, opponentState in pairs(LatestGameState.Players) do
    if opponentState.id ~= BotID and inRange(x, y, opponentState.x, opponentState.y, dangerZoneRange) then
      return true -- The position is dangerous because another player is too close
    end
  end
  return false -- The position is not dangerous
end

-- Function to calculate a danger score for a position
function calculateDangerScore(x, y)
  local dangerScore = 0
  local checkRange = 5 -- The range to check for nearby players

  for _, opponentState in pairs(LatestGameState.Players) do
    if opponentState.id ~= BotID then
      -- Increase the danger score the closer the opponent is
      local distance = calculateDistance(x, y, opponentState.x, opponentState.y)
      if distance < checkRange then
        dangerScore = dangerScore + (checkRange - distance) -- Closer opponents contribute more to the danger score
      end
    end
  end

  return dangerScore
end

-- Helper function to calculate the distance between two points
function calculateDistance(x1, y1, x2, y2)
  return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

  
  -- Check each direction for safety
  for direction, vector in pairs(directionMap) do
    local newX = (playerState.x + vector.x - 1) % Width + 1
    local newY = (playerState.y + vector.y - 1) % Height + 1
    

    -- If the new position is not dangerous, consider moving there
    if not isPositionDangerous(newX, newY) then
      local dangerScore = calculateDangerScore(newX, newY)
      if dangerScore < leastDangerousScore then
        leastDangerousScore = dangerScore
        safestDirection = direction
      end
    end
  end

  return safestDirection
end

-- Function to update the bot's strategy based on the number of remaining players
function updateStrategy()
  -- Update strategy based on the number of remaining players
  if RemainingPlayers <= (TotalPlayers / 2) then
    -- If half the players have been eliminated, switch to a more aggressive strategy
    playerState.attackThreshold = math.max(10, playerState.attackThreshold * 0.8) -- Lower threshold to attack more often
  elseif RemainingPlayers <= (TotalPlayers / 4) then
    -- If only a quarter of the players remain, switch to a defensive strategy
    playerState.attackThreshold = math.min(50, playerState.attackThreshold * 1.2) -- Raise threshold to attack less often
  end
end

-- Function to handle the elimination of a player
function onPlayerEliminated(eliminatedPlayerID)
  -- Decrement the count of remaining players
  RemainingPlayers = RemainingPlayers - 1
  -- Update the bot's strategy based on the new player count
  updateStrategy()
end

-- Function to react when the bot is attacked
function onAttacked(attackerID)
  local playerState = LatestGameState.Players[BotID]
  -- Decide whether to retaliate or retreat based on the bot's current state
  if playerState.health < 50 or playerState.energy < 20 then
    -- Retreat to a safer position if health or energy is low
    local safeDirection = findSafestDirection(playerState)
    performMove(safeDirection)
  else
    -- Retaliate if health and energy are sufficient
    performAttack(attackerID)
  end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "gameModeBegins",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    gameModeBegins()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

