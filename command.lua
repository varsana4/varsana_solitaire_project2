local CommandSystem = {}

local cardPlaceSound
local PILE_TYPE

function CommandSystem.init(sound, pileTypes)
    cardPlaceSound = sound
    PILE_TYPE = pileTypes
end

local CommandManager = {}

function CommandManager:new(maxHistory)
    local obj = {
        history = {},
        maxHistory = maxHistory or 50,
        currentIndex = 0
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function CommandManager:executeCommand(command)
    if self.currentIndex < #self.history then
        for i = #self.history, self.currentIndex + 1, -1 do
            table.remove(self.history, i)
        end
    end
    
    command:execute()
    
    table.insert(self.history, command)
    self.currentIndex = #self.history
    
    if #self.history > self.maxHistory then
        table.remove(self.history, 1)
        self.currentIndex = #self.history
    end
end

function CommandManager:undo()
    if self.currentIndex > 0 then
        local command = self.history[self.currentIndex]
        command:undo()
        self.currentIndex = self.currentIndex - 1
    end
end

function CommandManager:redo()
    if self.currentIndex < #self.history then
        self.currentIndex = self.currentIndex + 1
        local command = self.history[self.currentIndex]
        command:execute()
    end
end

function CommandManager:clearHistory()
    self.history = {}
    self.currentIndex = 0
end

CommandSystem.CommandManager = CommandManager

local function shuffleCards(cards)
    local cardCount = #cards
    for i = cardCount, 2, -1 do
        local j = math.random(i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    return cards
end

local DrawStockCommand = {}

function DrawStockCommand:new(stockPile, wastePile)
    local obj = {
        stockPile = stockPile,
        wastePile = wastePile,
        drawnCards = {}
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function DrawStockCommand:execute()
    local drawnCount = math.min(3, #self.stockPile.cards)
    
    for i = 1, drawnCount do
        local card = self.stockPile:removeTopCard()
        if card then
            card:flip()
            table.insert(self.drawnCards, card)
            self.wastePile:addCard(card)
        end
    end
    
    if #self.wastePile.cards < 3 and #self.stockPile.cards == 0 then
        local recycleableCards = #self.wastePile.cards - #self.drawnCards
        if recycleableCards > 0 then
            _G.needsReset = true
        end
    end
    
    if #self.drawnCards > 0 and cardPlaceSound then
        cardPlaceSound:stop()
        cardPlaceSound:play()
    end
end

function DrawStockCommand:undo()
    for i = 1, #self.drawnCards do
        local card = self.wastePile:removeTopCard()
        if card then
            card:flip()
            self.stockPile:addCard(card)
        end
    end
    self.drawnCards = {}
end

CommandSystem.DrawStockCommand = DrawStockCommand

local ResetStockCommand = {}

function ResetStockCommand:new(stockPile, wastePile)
    local obj = {
        stockPile = stockPile,
        wastePile = wastePile,
        cards = {},
        originalOrder = {} 
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function ResetStockCommand:execute()
   
    local tempCards = {}
    while #self.wastePile.cards > 0 do
        local card = self.wastePile:removeTopCard()
        table.insert(tempCards, card)
        card:flip() 
     
        table.insert(self.originalOrder, card)
    end
 
    shuffleCards(tempCards)
  
    for _, card in ipairs(tempCards) do
        self.stockPile:addCard(card)
        table.insert(self.cards, card) 
    end

    if #self.stockPile.cards >= 3 then
        for i = 1, 3 do
            local card = self.stockPile:removeTopCard()
            if card then
                card:flip()
                self.wastePile:addCard(card)
            end
        end
    elseif #self.stockPile.cards > 0 then
       
        for i = 1, #self.stockPile.cards do
            local card = self.stockPile:removeTopCard()
            if card then
                card:flip() 
                self.wastePile:addCard(card)
            end
        end
    end
    
    if #self.cards > 0 and cardPlaceSound then
        cardPlaceSound:stop()
        cardPlaceSound:play()
    end
end

function ResetStockCommand:undo()
    while #self.wastePile.cards > 0 do
        local card = self.wastePile:removeTopCard()
        card:flip() 
     
        table.insert(self.stockPile.cards, 1, card)
    end

    while #self.stockPile.cards > 0 do
        self.stockPile:removeTopCard()
    end

    for i = #self.originalOrder, 1, -1 do
        local card = self.originalOrder[i]
        card:flip() 
        self.wastePile:addCard(card)
    end
    
    self.cards = {}
    self.originalOrder = {}
end

CommandSystem.ResetStockCommand = ResetStockCommand


local MoveCardCommand = {}

function MoveCardCommand:new(cards, sourcePile, targetPile, pileTypes)
    local obj = {
        cards = cards,
        sourcePile = sourcePile,
        targetPile = targetPile,
        revealedCard = nil,
        pileTypes = pileTypes
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function MoveCardCommand:execute()
    for _, card in ipairs(self.cards) do
        self.targetPile:addCard(card)
    end
    

    if self.sourcePile and self.sourcePile.pileType == self.pileTypes.TABLEAU then
        local topCard = self.sourcePile:getTopCard()
        if topCard and not topCard.faceUp then
            topCard:flip()
            self.revealedCard = topCard
        end
    end
    

    if self.sourcePile and self.sourcePile.pileType == self.pileTypes.WASTE then
  
        self:refillWaste()
    end
    
    if cardPlaceSound then
        cardPlaceSound:stop()
        cardPlaceSound:play()
    end
end

function MoveCardCommand:refillWaste()

    local stockPile = _G.stockPile 
    local wastePile = _G.wastePile  
    
    if stockPile and wastePile then
  
        local neededCards = 3 - #wastePile.cards
        if neededCards > 0 and #stockPile.cards > 0 then
            local drawnCount = math.min(neededCards, #stockPile.cards)
            
            for i = 1, drawnCount do
                local card = stockPile:removeTopCard()
                if card then
                    card:flip()
                    wastePile:addCard(card)
                end
            end

            if #wastePile.cards < 3 and #stockPile.cards == 0 then
              
                local recycleableCards = #wastePile.cards - 1  
                if recycleableCards > 0 then
                    _G.needsReset = true
                end
            end
        end
    end
end

function MoveCardCommand:undo()
    if self.revealedCard then
        self.revealedCard:flip()
        self.revealedCard = nil
    end
    
    if self.sourcePile and self.sourcePile.pileType == self.pileTypes.WASTE then
        self:undoRefillWaste()
    end

    local removedCards = {}
    for i = 1, #self.cards do
        local card = self.targetPile:removeTopCard()
        if card then
            table.insert(removedCards, 1, card)
        end
    end

    for _, card in ipairs(removedCards) do
        if self.sourcePile then
            self.sourcePile:addCard(card)
        end
    end
end

function MoveCardCommand:undoRefillWaste()
    local stockPile = _G.stockPile
    local wastePile = _G.wastePile

    if stockPile and wastePile then
        local desiredWasteCount = math.min(3, #stockPile.cards + #wastePile.cards)

          while #wastePile.cards < desiredWasteCount and #stockPile.cards > 0 do
            local card = stockPile:removeTopCard()
            if card then
                card:flip()
                wastePile:addCard(card)
            end
        end
    end
end

CommandSystem.MoveCardCommand = MoveCardCommand


local AutoFillWasteCommand = {}

function AutoFillWasteCommand:new(stockPile, wastePile)
    local obj = {
        stockPile = stockPile,
        wastePile = wastePile,
        drawnCards = {}
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function AutoFillWasteCommand:execute()
    local neededCards = 3 - #self.wastePile.cards
    
    if neededCards > 0 and #self.stockPile.cards > 0 then
        local drawnCount = math.min(neededCards, #self.stockPile.cards)
        
        for i = 1, drawnCount do
            local card = self.stockPile:removeTopCard()
            if card then
                card:flip() 
                table.insert(self.drawnCards, card)
                self.wastePile:addCard(card)
            end
        end
        
        if #self.drawnCards > 0 and cardPlaceSound then
            cardPlaceSound:stop()
            cardPlaceSound:play()
        end
    end
end

function AutoFillWasteCommand:undo()
      for i = 1, #self.drawnCards do
        local card = self.wastePile:removeTopCard()
        if card then
            card:flip() 
            self.stockPile:addCard(card)
        end
    end
    self.drawnCards = {}
end

CommandSystem.AutoFillWasteCommand = AutoFillWasteCommand

return CommandSystem