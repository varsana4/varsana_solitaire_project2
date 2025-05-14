io.stdout:setvbuf("no")
require "card"
require "grabber"
require "vector"
local Pile = require "pile"
local CommandSystem = require "command"

local CARD_WIDTH = 80
local CARD_HEIGHT = 120
local VERTICAL_SPACING = 30
local HORIZONTAL_SPACING = 20
local WASTE_OFFSET = 20

local SUITS = {"hearts", "diamonds", "clubs", "spades"}
local VALUES = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13} 

local PILE_TYPE = Pile.PILE_TYPE
local PileClass = Pile.PileClass

local cardPlaceSound = love.audio.newSource("sounds/flipcard-91468.mp3", "static")
local shuffleSound = love.audio.newSource("sounds/shuffle-92719.mp3", "static")
local victorySound = love.audio.newSource("sounds/success-1-6297.mp3", "static")

local isFirstLoad = true
local isMuted = false

local grabber
local stockPile
local wastePile
local foundationPiles
local tableauPiles
local draggedCards
local dragOriginPile

local commandManager

local resetButton
local undoButton
local muteButton

gameOver = false

_G.stockPile = nil
_G.wastePile = nil
_G.needsReset = false

local ButtonClass = {}

function ButtonClass:new(x, y, width, height, text, action)
  local obj = {
    x = x,
    y = y,
    width = width,
    height = height,
    text = text,
    action = action,
    isHovered = false
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function ButtonClass:update(mouseX, mouseY)
  self.isHovered = mouseX >= self.x and mouseX <= self.x + self.width and
                   mouseY >= self.y and mouseY <= self.y + self.height
end

function ButtonClass:draw()
  if self.isHovered then
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
  else
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
  end
  love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 5, 5)
  
  love.graphics.setColor(0.3, 0.3, 0.3, 1)
  love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 5, 5)
  
  love.graphics.setColor(0, 0, 0, 1)
  local font = love.graphics.getFont()
  local textWidth = font:getWidth(self.text)
  local textHeight = font:getHeight()
  love.graphics.print(self.text, 
    self.x + (self.width - textWidth) / 2, 
    self.y + (self.height - textHeight) / 2)
  
  love.graphics.setColor(1, 1, 1, 1)
end

function ButtonClass:isPointInside(x, y)
  return x >= self.x and x <= self.x + self.width and
         y >= self.y and y <= self.y + self.height
end

function love.load()
  math.randomseed(os.time())
  love.window.setMode(960, 640)
  love.graphics.setBackgroundColor(0, 0.7, 0.2, 1)
    
  CardClass.loadImages()
   
  grabber = GrabberClass:new()
  
  CommandSystem.init(cardPlaceSound, PILE_TYPE)
  
  commandManager = CommandSystem.CommandManager:new(50)
  
  resetButton = ButtonClass:new(820, 580, 120, 40, "Reset", function() 
    gameOver = false
    initializeGame() 
  end)
  
  undoButton = ButtonClass:new(680, 580, 120, 40, "Undo", function() 
    commandManager:undo() 
  end)
  
  muteButton = ButtonClass:new(540, 580, 120, 40, "Mute", function()
    isMuted = not isMuted
    if isMuted then
      love.audio.setVolume(0)
      muteButton.text = "Unmute"
    else
      love.audio.setVolume(1)
      muteButton.text = "Mute"
    end
  end)
  
  initializeGame()
end

function initializeGame()
  math.randomseed(os.time())
  
  if commandManager then
    commandManager:clearHistory()
  else
    commandManager = CommandSystem.CommandManager:new(50)
  end

  local deck = {}
  for _, suit in ipairs(SUITS) do
    for _, value in ipairs(VALUES) do
      table.insert(deck, CardClass:new(0, 0, suit, value))
    end
  end
  
  for i = #deck, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
  
  if not isFirstLoad and shuffleSound then
    shuffleSound:stop()
    shuffleSound:play()
  end
  isFirstLoad = false

  local totalTableauWidth = (7 * CARD_WIDTH) + (6 * HORIZONTAL_SPACING)
  local firstPileX = (960 - totalTableauWidth) / 2

  stockPile = PileClass:new(50, 50, PILE_TYPE.STOCK)
  wastePile = PileClass:new(200, 50, PILE_TYPE.WASTE)
  
  _G.stockPile = stockPile
  _G.wastePile = wastePile
  _G.needsReset = false
  
  local foundationPositions = {}
  for i = 1, 4 do
    table.insert(foundationPositions, {
      x = firstPileX + (i+1) * (CARD_WIDTH + HORIZONTAL_SPACING),
      y = 50
    })
  end

  foundationPiles = {}
  for i = 1, 4 do
    foundationPiles[i] = PileClass:new(
      foundationPositions[i].x,
      foundationPositions[i].y,
      PILE_TYPE.FOUNDATION
    )
  end

  tableauPiles = {}
  for i = 1, 7 do
    tableauPiles[i] = PileClass:new(
      firstPileX + (i-1) * (CARD_WIDTH + HORIZONTAL_SPACING),
      180,  
      PILE_TYPE.TABLEAU
    )
  end

  for i = 1, 7 do
    for j = 1, i do
      local card = table.remove(deck)
      if j == i then
        card:flip()
      end
      tableauPiles[i]:addCard(card)
    end
  end
  
  for _, card in ipairs(deck) do
    stockPile:addCard(card)
  end
  deck = nil

  draggedCards = {}
  dragOriginPile = nil
end

function love.update(dt)
  grabber:update()
  
  stockPile:update()
  wastePile:update()
  
  for _, pile in ipairs(foundationPiles) do
    pile:update()
  end
  
  for _, pile in ipairs(tableauPiles) do
    pile:update()
  end
  
  updateDrag()
  
  if _G.needsReset and #stockPile.cards == 0 and #wastePile.cards > 0 then
    local resetCommand = CommandSystem.ResetStockCommand:new(stockPile, wastePile)
    commandManager:executeCommand(resetCommand)
    _G.needsReset = false
  end
  
  local mouseX, mouseY = love.mouse.getPosition()
  resetButton:update(mouseX, mouseY)
  undoButton:update(mouseX, mouseY)
  muteButton:update(mouseX, mouseY)  
  
  if not grabber.isDragging then
    checkForMouseInteractions()
  end
  
  if not gameOver then
    checkForGameOver()
  end
end

function love.draw()
  stockPile:draw()
  wastePile:draw()

  for _, pile in ipairs(foundationPiles) do
    pile:draw()
  end

  for _, pile in ipairs(tableauPiles) do
    pile:draw()
  end

  for _, card in ipairs(draggedCards) do
    card:draw()
  end
  
  resetButton:draw()
  undoButton:draw()
  muteButton:draw()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Mouse: " .. tostring(grabber.currentMousePos.x) .. ", " .. tostring(grabber.currentMousePos.y), 10, 10)

  love.graphics.setColor(1, 0, 0, 0.3)
  for _, pile in ipairs(tableauPiles) do
    local pileBottom = pile.y + pile.height
    if #pile.cards > 0 then
      pileBottom = pile.y + (#pile.cards - 1) * VERTICAL_SPACING + pile.height
    end
    love.graphics.rectangle("line", pile.x, pile.y, pile.width, pileBottom - pile.y)
  end
  love.graphics.setColor(1, 1, 1, 1)

  if #draggedCards > 0 then
    love.graphics.setColor(0, 1, 0, 0.2)
    for _, pile in ipairs(tableauPiles) do
      if canPlaceCards(draggedCards, pile) then
        love.graphics.rectangle("fill", pile.x - 5, pile.y - 5, pile.width + 10, pile.height + 10, 5)
      end
    end
    
    if #draggedCards == 1 then
      for _, pile in ipairs(foundationPiles) do
        if canPlaceCards(draggedCards, pile) then
          love.graphics.rectangle("fill", pile.x - 5, pile.y - 5, pile.width + 10, pile.height + 10, 5)
        end
      end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
  end

  if #stockPile.cards == 0 and #wastePile.cards > 0 then
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.print(" DECK", stockPile.x + 10, stockPile.y + 50)
    love.graphics.setColor(1, 1, 1, 1)
  end
  
  if gameOver then
    love.graphics.setColor(1, 1, 1)
    local message = "You Win!"
    local textWidth = love.graphics.getFont():getWidth(message)
    local textHeight = love.graphics.getFont():getHeight()
    love.graphics.print(message, (love.graphics.getWidth() - textWidth) / 2, (love.graphics.getHeight() - textHeight) / 2 - 20)
    
    message = "Click Reset Button to restart the game"
    textWidth = love.graphics.getFont():getWidth(message)
    textHeight = love.graphics.getFont():getHeight()
    love.graphics.print(message, (love.graphics.getWidth() - textWidth) / 2, (love.graphics.getHeight() - textHeight) / 2 + 20)
  end
end

function safeCardOffset(x, y, card)
  if card and type(card.x) == "number" and type(card.y) == "number" then
    return x - card.x, y - card.y
  else
    return 0, 0
  end
end

function love.mousepressed(x, y, button)
  if button ~= 1 then return end
  
  if resetButton:isPointInside(x, y) then
    resetButton.action()
    return
  end
  
  if undoButton:isPointInside(x, y) then
    undoButton.action()
    return
  end
  
  if muteButton:isPointInside(x, y) then
    muteButton.action()
    return
  end
  
  draggedCards = {}
  dragOriginPile = nil

  if stockPile:isPointInside(x, y) then
    if #stockPile.cards > 0 then
      local drawCommand = CommandSystem.DrawStockCommand:new(stockPile, wastePile)
      commandManager:executeCommand(drawCommand)
    elseif #wastePile.cards > 0 then
      local resetCommand = CommandSystem.ResetStockCommand:new(stockPile, wastePile)
      commandManager:executeCommand(resetCommand)
    end
    return
  end
  
  if #wastePile.cards > 0 and wastePile:isPointInside(x, y) then
    local cardIndex = wastePile:findCardAt(x, y)
    if cardIndex > 0 then
      local card = wastePile:getTopCard()
      local offsetX, offsetY = safeCardOffset(x, y, card)
      
      local removedCard = wastePile:removeTopCard()
      if removedCard then
        table.insert(draggedCards, removedCard)
        dragOriginPile = wastePile
        for _, c in ipairs(draggedCards) do
          c.originalX, c.originalY = c.x, c.y
        end
        
        grabber:startDrag(x, y, offsetX, offsetY)
      end
      return
    end
  end

  for _, pile in ipairs(foundationPiles) do
    if #pile.cards > 0 and pile:isPointInside(x, y) then
      local card = pile:getTopCard()
      if card and card:isPointInside(x, y) then
        local offsetX, offsetY = safeCardOffset(x, y, card)
        local removedCard = pile:removeTopCard()
        if removedCard then
          table.insert(draggedCards, removedCard)
          dragOriginPile = pile
          for _, c in ipairs(draggedCards) do
            c.originalX, c.originalY = c.x, c.y
          end
          grabber:startDrag(x, y, offsetX, offsetY)
        end
        return
      end
    end
  end

  for _, pile in ipairs(tableauPiles) do
    if #pile.cards > 0 then
      local cardIndex = pile:findCardAt(x, y)
      if cardIndex > 0 and pile.cards[cardIndex].faceUp then
        local topCard = pile.cards[cardIndex]
        local offsetX, offsetY = safeCardOffset(x, y, topCard)
        local cardsToMove = pile:removeCards(cardIndex)

        if cardsToMove and #cardsToMove > 0 then
          for _, c in ipairs(cardsToMove) do
            table.insert(draggedCards, c)
          end
          dragOriginPile = pile
          for _, c in ipairs(draggedCards) do
            c.originalX, c.originalY = c.x, c.y
          end
          grabber:startDrag(x, y, offsetX, offsetY)
        end
        return
      end
    end
  end
end

function love.mousereleased(x, y, button)
  if button == 1 and #draggedCards > 0 then
    local targetPile = nil
    local closestDist = math.huge

    if #draggedCards == 1 and draggedCards[1] then
      local card = draggedCards[1]
      if card.value == 1 then
        for _, pile in ipairs(foundationPiles) do
          if #pile.cards == 0 then
            local pileCenterX = pile.x + pile.width / 2
            local pileCenterY = pile.y + pile.height / 2
            local dist = math.sqrt((x - pileCenterX)^2 + (y - pileCenterY)^2)
            if dist < closestDist then
              closestDist = dist
              targetPile = pile
            end
          end
        end
      end
      if not targetPile then
        for _, pile in ipairs(foundationPiles) do
          if #pile.cards > 0 and canPlaceCards(draggedCards, pile) then
            local pileCenterX = pile.x + pile.width / 2
            local pileCenterY = pile.y + pile.height / 2
            local dist = math.sqrt((x - pileCenterX)^2 + (y - pileCenterY)^2)
            if dist < closestDist then
              closestDist = dist
              targetPile = pile
            end
          end
        end
      end
    end

    if not targetPile then
      closestDist = math.huge
      for _, pile in ipairs(tableauPiles) do
        if canPlaceCards(draggedCards, pile) then
          local pileCenterX = pile.x + pile.width / 2
          local pileCenterY = pile.y + pile.height / 2
          local dist = math.sqrt((x - pileCenterX)^2 + (y - pileCenterY)^2)
          if dist < closestDist then
            closestDist = dist
            targetPile = pile
          end
        end
      end
    end

    if targetPile then
      local cardsCopy = {}
      for i = 1, #draggedCards do
        cardsCopy[i] = draggedCards[i]
      end
      
      local moveCommand = CommandSystem.MoveCardCommand:new(cardsCopy, dragOriginPile, targetPile, PILE_TYPE)
      commandManager:executeCommand(moveCommand)
    else
      if dragOriginPile then
        for _, card in ipairs(draggedCards) do
          if card then
            dragOriginPile:addCard(card)
          end
        end
      end
    end

    draggedCards = {}
    grabber:endDrag()
  end
end

function updateDrag()
  if grabber and grabber.isDragging and #draggedCards > 0 and 
     grabber.currentMousePos and type(grabber.currentMousePos.x) == "number" and 
     type(grabber.currentMousePos.y) == "number" and
     grabber.dragOffset and type(grabber.dragOffset.x) == "number" and 
     type(grabber.dragOffset.y) == "number" then
    
    local mouseX = grabber.currentMousePos.x
    local mouseY = grabber.currentMousePos.y
    
    for i, card in ipairs(draggedCards) do
      if card then
        card.x = mouseX - grabber.dragOffset.x
        card.y = mouseY - grabber.dragOffset.y + (i-1) * VERTICAL_SPACING 
      end
    end
  end
end

function checkForMouseInteractions()
  local mouseX = grabber.currentMousePos.x
  local mouseY = grabber.currentMousePos.y
  local isOverCard = false

  if stockPile:isPointInside(mouseX, mouseY) then
    isOverCard = true
  end

  if wastePile:isPointInside(mouseX, mouseY) then
    isOverCard = true
  end

  for _, pile in ipairs(foundationPiles) do
    if pile:isPointInside(mouseX, mouseY) then
      isOverCard = true
      break
    end
  end

  for _, pile in ipairs(tableauPiles) do
    if pile:findCardAt(mouseX, mouseY) > 0 then
      isOverCard = true
      break
    end
  end
  
  if resetButton.isHovered or undoButton.isHovered or muteButton.isHovered then
    isOverCard = true
  end

  if isOverCard then
    love.mouse.setCursor(love.mouse.getSystemCursor("hand"))
  else
    love.mouse.setCursor()
  end
end

function canPlaceCards(cards, targetPile)
  if #cards == 0 then return false end

  local bottomCard = cards[1]
  if not bottomCard then return false end

  if targetPile.pileType == PILE_TYPE.FOUNDATION then
    if #cards > 1 then return false end

    if #targetPile.cards == 0 then
      return bottomCard.value == 1
    end

    local topCard = targetPile:getTopCard()
    if not topCard then return false end

    return bottomCard.suit == topCard.suit and
           bottomCard.value == topCard.value + 1
  end

  if targetPile.pileType == PILE_TYPE.TABLEAU then
    local topCard = targetPile:getTopCard()

    if not topCard then
      return bottomCard.value == 13
    end

    local bottomIsRed = bottomCard.suit == "hearts" or bottomCard.suit == "diamonds"
    local topIsRed = topCard.suit == "hearts" or topCard.suit == "diamonds"

    return bottomIsRed ~= topIsRed and
           bottomCard.value == topCard.value - 1
  end

  return false
end

function checkForGameOver()
  for _, pile in ipairs(foundationPiles) do
    if #pile.cards < 13 then
      return 
    end
  end
  gameOver = true
  
  if victorySound then
    victorySound:stop() 
    victorySound:play()
  end
end

