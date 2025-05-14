local CARD_WIDTH = 80
local CARD_HEIGHT = 120
local VERTICAL_SPACING = 30
local WASTE_OFFSET = 20

local PILE_TYPE = {
  STOCK = "stock",
  WASTE = "waste",
  FOUNDATION = "foundation",
  TABLEAU = "tableau"
}

local PileClass = {}

function PileClass:new(x, y, pileType)
  local obj = {
    x = x,
    y = y,
    width = CARD_WIDTH,
    height = CARD_HEIGHT,
    pileType = pileType,
    cards = {}
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function PileClass:update()
  for i, card in ipairs(self.cards) do
    if self.pileType == PILE_TYPE.TABLEAU then
      card.x = self.x
      card.y = self.y + (i - 1) * VERTICAL_SPACING
    else
      card.x = self.x
      card.y = self.y
    end
  end
end

function PileClass:draw()
  love.graphics.setColor(1, 1, 1, 0.2)
  love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 5, 5)
  love.graphics.setColor(1, 1, 1, 1)

  if self.pileType == PILE_TYPE.TABLEAU then
    for _, card in ipairs(self.cards) do
      card:draw()
    end
  elseif self.pileType == PILE_TYPE.WASTE then
    local startIndex = math.max(1, #self.cards - 2)
    for i = startIndex, #self.cards do
      love.graphics.push()
      love.graphics.translate((i - startIndex) * WASTE_OFFSET, 0)
      self.cards[i]:draw()
      love.graphics.pop()
    end
  else
    if #self.cards > 0 then
      self.cards[#self.cards]:draw()
    end
  end
end

function PileClass:isEmpty()
  return #self.cards == 0
end

function PileClass:addCard(card)
  card.x = self.x
  card.y = self.y
  
  if self.pileType == PILE_TYPE.TABLEAU then
    if #self.cards > 0 then
      card.y = self.y + (#self.cards * VERTICAL_SPACING)
    end
  end
  
  table.insert(self.cards, card)
end

function PileClass:getTopCard()
  if #self.cards > 0 then
    return self.cards[#self.cards]
  end
  return nil
end

function PileClass:removeTopCard()
  if #self.cards > 0 then
    local card = table.remove(self.cards, #self.cards)
    return card
  end
  return nil
end

function PileClass:removeCards(startIndex)
  local removedCards = {}

  if startIndex <= #self.cards then
    while #self.cards >= startIndex do
      local card = table.remove(self.cards)
      table.insert(removedCards, 1, card)
    end
  end

  return removedCards
end

function PileClass:findCardAt(x, y)
  if self.pileType == PILE_TYPE.TABLEAU then
    for i = #self.cards, 1, -1 do
      local cardX = self.x
      local cardY = self.y + (i - 1) * VERTICAL_SPACING

      if x >= cardX and x <= cardX + self.width and
         y >= cardY and y <= cardY + self.height then
        return i
      end
    end
  elseif self.pileType == PILE_TYPE.WASTE and #self.cards > 0 then
    local startIndex = math.max(1, #self.cards - 2)

    for i = #self.cards, startIndex, -1 do
      local offset = (i - startIndex) * WASTE_OFFSET
      
      if x >= self.x + offset and x <= self.x + offset + CARD_WIDTH and
         y >= self.y and y <= self.y + CARD_HEIGHT then
        return #self.cards  
      end
    end
  else
    if #self.cards > 0 and
       x >= self.x and x <= self.x + self.width and
       y >= self.y and y <= self.y + self.height then
      return #self.cards
    end
  end

  return 0
end

function PileClass:isPointInside(x, y)
  local pileBottom = self.y + self.height

  if self.pileType == PILE_TYPE.TABLEAU and #self.cards > 0 then
    pileBottom = self.y + (#self.cards - 1) * VERTICAL_SPACING + self.height
  elseif self.pileType == PILE_TYPE.WASTE and #self.cards > 0 then
    local visibleCards = math.min(3, #self.cards)
    local totalWidth = self.width + (visibleCards - 1) * WASTE_OFFSET
    
    return x >= self.x and x <= self.x + totalWidth and
           y >= self.y and y <= self.y + self.height
  end
  
  return x >= self.x and x <= self.x + self.width and
         y >= self.y and y <= pileBottom
end

function PileClass:ensureTopCardFaceUp()
  if #self.cards > 0 and not self.cards[#self.cards].faceUp then
    self.cards[#self.cards].faceUp = true
  end
end

return {
  PileClass = PileClass,
  PILE_TYPE = PILE_TYPE
}