local LEVEL_WIDTH = 16
local LEVEL_HEIGHT = 14
local GRAVITY = 0.125
local LEVEL_TRANSITION_TIMER_MAX = 60
local SHOWN_SIGN_TIMER_MAX = 10
local TITLE_TIMER_MAX = 120
local LEVEL_COMPLETE_TIMER_MAX = 30

local currentLevel
local bumpWorld
local entities
local bullets
local switches
local cameraShake
local locks
local levelTransitionTimer
local shownSignTimer
local levelTransitionCallback
local titleTimer
local levelCompleteTimer

local STATES = {
    TITLE = 'TITLE',
    GAME = 'GAME',
    SELECT = 'SELECT',
}
local state

local function printCentre(text, y, color)
    print(text, (128 - #text * 4)/2, y, color)
end

local function loadLevelProgress(levelNumber)
    local data = dget(levelNumber - 1)
    local isComplete = (data & 1) == 1
    local hasMedal = (data & 2) == 2
    return isComplete, hasMedal
end

local function saveLevelProgress(levelNumber, isComplete, hasMedal)
    local data = 0
    if isComplete then
        data = data | 1
    end
    if hasMedal then
        data = data | 2
    end
    dset(levelNumber - 1, data)
end

local Entity = Object:extend()

function Entity:new(x, y, width, height)
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    bumpWorld:add(self, self.x, self.y, self.width, self.height)
    self.isDestroyed = false
end

function Entity:getPlayerCollisionType()
    return 'slide'
end

function Entity:getBulletCollisionType()
    return self:getPlayerCollisionType()
end

function Entity:update()
    --
end

function Entity:draw()
    --
end

function Entity:destroy()
    bumpWorld:remove(self, self.y, self.y, self.width, self.height)
    self.isDestroyed = true
end


local SWITCH_COLORS = {
    RED = 8,
    GREEN = 11,
    BLUE = 12,
}

local Switch = Entity:extend()

function Switch:new(x, y, color)
    Switch.super.new(self, x, y, 8, 8)
    self.color = color
    self.isDisabled = false
end

function Switch:draw()
    local colorCode = self.color
    if self.isDisabled then
        colorCode = 7
    end
    fillp('0b0101101001011010.1')
    circfill(self.x + 4, self.y + 4, 4, colorCode)
    fillp()
    circ(self.x + 4, self.y + 4, 4, self.color)
end

function Switch:getPlayerCollisionType()
    return 'cross'
end

function Switch:getBulletCollisionType()
    return 'cross'
end

local Lock = Entity:extend()

function Lock:new(x, y)
    Switch.super.new(self, x, y, 8, 8)
    self.isDisabled = false
    self.spriteIndex = 0
end

function Lock:update()
    self.spriteIndex = self.spriteIndex + 1
end

Lock.ENABLED_SPRITES = {
    29, 14, 30, 15, 31,
}
Lock.DISABLED_SPRITE = 45
function Lock:draw()
    if self.isDisabled then
        spr(Lock.DISABLED_SPRITE, self.x, self.y)
    else
        spr(Lock.ENABLED_SPRITES[flr(self.spriteIndex/4) % #Lock.ENABLED_SPRITES + 1], self.x, self.y)
    end
end

function Lock:getPlayerCollisionType()
    return 'cross'
end

function Lock:getBulletCollisionType()
    return 'cross'
end


local Sign = Entity:extend()

function Sign:new(x, y, text)
    Switch.super.new(self, x, y, 8, 8)
    self.text = text
end

function Sign:draw()
    palt(14, true)
    palt(0, false)
    spr(13, self.x, self.y)
    palt(14, false)
    palt(0, true)
    -- Fuzzy screen
    fillp(flr(rnd(0x8000)))
    rectfill(self.x + 1, self.y + 1, self.x + 6, self.y + 4, 11)
    fillp()
end

function Sign:getPlayerCollisionType()
    return 'cross'
end

function Sign:getBulletCollisionType()
    return nil
end


local Wall = Entity:extend()

function Wall:draw()
    -- rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 7)
end


local Fence = Wall:extend()

function Fence:getBulletCollisionType()
    return nil
end

function Fence:draw()
    fillp('0b0101101001011010.1')
    rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 6)
    fillp()
end


local SwitchWall = Wall:extend()
SwitchWall.FILL_PATTERNS = {
    '0b1111000000000000.1',
    '0b0000111100000000.1',
    '0b0000000011110000.1',
    '0b0000000000001111.1',
}

function SwitchWall:new(x, y, width, height, color)
    SwitchWall.super.new(self, x, y, width, height)
    self.color = color
    self.fillPatternIndex = 0
end

function SwitchWall:update()
    self.fillPatternIndex = self.fillPatternIndex + 1
end

function SwitchWall:isDisabled()
    for switch in all(switches) do
        if switch.isDisabled and switch.color == self.color then
            return true
        end
    end
    return false
end

function SwitchWall:getPlayerCollisionType()
    if self:isDisabled() then
        return nil
    end
    return 'slide'
end

function SwitchWall:draw()
    if not self:isDisabled() then
        fillp(SwitchWall.FILL_PATTERNS[self.fillPatternIndex % #SwitchWall.FILL_PATTERNS + 1])
        rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, self.color)
        fillp()
    end
end


local Bullet = Entity:extend()
-- _ used instead of . to allow these vars to be minified
Bullet.SPEED = 3
Bullet.MAX_BOUNCES = 4
Bullet.DEATH_TIMER_MAX = 30
Bullet.TRAIL_LENGTH = 32
Bullet.COLORS = {
    [0] = { 7, 10 },
    [1] = { 10, 9 },
    [2] = { 9, 8 },
    [3] = { 8, 2 },
}
Bullet.MAX_LIFE = (8 * 32/Bullet.SPEED) * Bullet.MAX_BOUNCES + Bullet.DEATH_TIMER_MAX

function Bullet:new(x, y, angle)
    Bullet.super.new(self, x, y, 4, 4)
    self.velX = cos(angle)
    self.velY = sin(angle)
    self.bounces = 0
    self.lastPositions = {}
    self.deathTimer = 0
    self.timeAlive = 0
end

function Bullet:destroy()
    Bullet.super.destroy(self)
    del(bullets, self)
end

function Bullet:getPlayerCollisionType()
    return nil
end

function Bullet:moveFilter(other)
    return other:getBulletCollisionType()
end

function Bullet:getBulletCollisionType()
    -- Don't collide with other bullets
    return nil
end

function Bullet:update()
    if self.bounces < Bullet.MAX_BOUNCES then
        local goalX = self.x + Bullet.SPEED * self.velX
        local goalY = self.y + Bullet.SPEED * self.velY
        self.x, self.y, collisions, _ = bumpWorld:move(self, goalX, goalY, self.moveFilter)
        for _, collision in ipairs(collisions) do
            if collision.other:is(Wall) then
                self.bounces = self.bounces + 1
                if collision.normal.y ~= 0 then
                    self.velY = self.velY * -1
                end
                if collision.normal.x ~= 0 then
                    self.velX = self.velX * -1
                end
            end
            if collision.other:is(Switch) and not collision.other.isDisabled then
                collision.other.isDisabled = true
            end
            if collision.other:is(Lock) and not collision.other.isDisabled then
                collision.other.isDisabled = true
            end
        end
        -- Keep track of previous positions for a trail effect, but no more than necessary.
        add(self.lastPositions, { x = self.x, y = self.y })
        while #self.lastPositions > Bullet.TRAIL_LENGTH do
            del(self.lastPositions, self.lastPositions[1])
        end
    else
        self.deathTimer = self.deathTimer + 1
        if self.deathTimer >= Bullet.DEATH_TIMER_MAX then
            self:destroy()
        end
        -- Keep updating the trail, just don't add anything new.
        if #self.lastPositions > 0 then
            del(self.lastPositions, self.lastPositions[1])
        end
    end
    -- insurance policy to prevent softlocking
    -- in case bullet clips through wall or something
    self.timeAlive = self.timeAlive + 1
    if self.timeAlive > Bullet.MAX_LIFE then
        self:destroy()
    end
end

function Bullet:draw()
    for i=1,Bullet.TRAIL_LENGTH,2 do
        -- rnd() call allows trail to diminish away from the bullet
        if i <= #self.lastPositions and rnd(Bullet.TRAIL_LENGTH) > i then
            local lastPosition = self.lastPositions[#self.lastPositions - i + 1]
            circfill(
                lastPosition.x + 2,
                lastPosition.y + 2,
                self.width/4,
                flr(rnd(15)) + 1
            )
        end
    end
    if self.bounces < Bullet.MAX_BOUNCES then
        circfill(
            self.x + 2,
            self.y + 2,
            self.width/2,
            Bullet.COLORS[self.bounces][ceil(rnd(2))]
        )
    else
        for i=1,4 do
            if rnd(Bullet.DEATH_TIMER_MAX) > self.deathTimer then
                local angle = i/4 + 0.4 * self.deathTimer/Bullet.DEATH_TIMER_MAX
                circfill(
                    self.x + 2 + 32 * cos(angle) * self.deathTimer/Bullet.DEATH_TIMER_MAX,
                    self.y + 2 + 32 * sin(angle) * self.deathTimer/Bullet.DEATH_TIMER_MAX,
                    self.width/4,
                    flr(rnd(15)) + 1
                )
            end
        end
    end
end

local Player = Entity:extend()
Player.SPEED = 1

function Player:new(x, y, bullets)
    Player.super.new(self, x, y, 8, 8)
    self.bullets = bullets
    self.velY = 0
    self.onGround = false
    -- point up to start
    self.angle = 0.25
    self.shownSign = nil
end

function Player:moveFilter(other)
    return other:getPlayerCollisionType()
end

function Player:getBulletCollisionType()
    return nil
end

function Player:update()
    local goalX = self.x
    local goalY = self.y

    if btn(5) then
        if btn(0) then
            self.angle = self.angle + 0.005
        elseif btn(1) then
            self.angle = self.angle - 0.005
        end
        self.angle = self.angle % 1
    else
        if btn(0) then
            goalX = goalX - Player.SPEED
        elseif btn(1) then
            goalX = goalX + Player.SPEED
        end
    end

    if btnp(2) then
        if self.onGround then
            self.velY = -2.5
        end
    end

    if btnp(4) and self.bullets > 0 then
        add(bullets, Bullet(self.x + 3, self.y + 3, self.angle))
        cameraShake = 1
        self.bullets = self.bullets - 1
    end

    goalY = goalY + self.velY
    self.velY = self.velY + GRAVITY

    local collisions
    -- Attempt to move player to goal position.
    self.x, self.y, collisions, _ = bumpWorld:move(self, goalX, goalY, self.moveFilter)
    -- Consider player to be on ground if not moving up (i.e. jumping) or
    -- not moving down beyond 1 pixel per frame (gives player a few frames to
    -- jump after falling off edge)
    if self.velY < 0 or self.velY >= 1 then
        self.onGround = false
    end

    -- Check collisions from player movement. We can ignore the wall collisions (except for
    -- controlling gravity) since bump has already handled them, but coin collisions are
    -- still important.
    self.shownSign = nil
    for _, collision in ipairs(collisions) do
        if collision.other:is(Wall) then
            -- Player has either landed or bonked wall above.
            if collision.normal.y ~= 0 then
                self.velY = 0
            end
            -- Player has landed!
            if collision.normal.y == -1 then
                self.onGround = true
            end
        elseif collision.other:is(Sign) then
            self.shownSign = collision.other
        end
    end
end

local LINE_LENGTH = 20
function Player:draw()
    local lineColorCode = 7
    if btn(5) then
        lineColorCode = 10
    end
    rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 12)
    rect(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 0)
    line(
        self.x + 4 + 2 * cos(self.angle),
        self.y + 4 + 2 * sin(self.angle),
        self.x + 4 + LINE_LENGTH * cos(self.angle),
        self.y + 4 + LINE_LENGTH * sin(self.angle),
        lineColorCode
    )
end

-- START MAIN
local player
local WALL_TILES = {
    1, 2, 3, 4, 5, 6,
    18, 19, 20, 21,
}

local function isInTable(x, xs)
    for cx in all(xs) do
        if x == cx then
            return true
        end
    end
    return false
end

local function isLevelComplete()
    for lock in all(locks) do
        if not lock.isDisabled then
            return false
        end
    end
    return true
end

local function hasMedalForLevel()
    return isLevelComplete() and (LEVELS[currentLevel].maxBullets - player.bullets) <= LEVELS[currentLevel].medalBullets
end

local function resetLevel(levelNumber)
    local levelData = LEVELS[levelNumber]
    bumpWorld = bump.newWorld(8)
    entities = {}
    switches = {}
    locks = {}
    bullets = {}
    for y=0, LEVEL_HEIGHT - 1 do
        for x=0, LEVEL_WIDTH - 1 do
            local tileIndex = 2 * (y * LEVEL_WIDTH + x) + 1
            local tile = tonum("0x"..sub(levelData.tiles, tileIndex, tileIndex + 1))
            mset(x, y, tile)
        end
    end
    for entity in all(levelData.entities) do
        if entity.entityType == "SPAWN" then
            player = Player(entity.x, entity.y, levelData.maxBullets)
        elseif entity.entityType == "LOCK" then
            add(locks, Lock(entity.x, entity.y))
        elseif entity.entityType == "SWITCH" then
            add(switches, Switch(entity.x, entity.y, SWITCH_COLORS[entity.props.color]))
        elseif entity.entityType == "SWITCH_WALL" then
            add(entities, SwitchWall(entity.x, entity.y, entity.width, entity.height, SWITCH_COLORS[entity.props.color]))
        elseif entity.entityType == "FENCE" then
            add(entities, Fence(entity.x, entity.y, entity.width, entity.height))
        elseif entity.entityType == "SIGN" then
            add(entities, Sign(
                entity.x, entity.y,
                { entity.props.text1, entity.props.text2 }
            ))
        end
    end
    -- Add border walls
    add(entities, Wall(0, 0, 128, 8))
    add(entities, Wall(0, 0, 8, 128))
    add(entities, Wall(0, 104, 128, 8))
    add(entities, Wall(120, 0, 8, 128))
    for wall in all(levelData.walls) do
        add(entities, Wall(wall[1], wall[2], wall[3], wall[4]))
    end
end

function initGame(initLevel)
    cameraShake = 0
    shownSignTimer = 0
    currentLevel = initLevel or 1
    resetLevel(currentLevel)
end

function updateSelf(self)
    self:update()
end

function updateGame()
    if not isLevelComplete() then
        player:update()
        levelCompleteTimer = 0
    else
        if levelCompleteTimer == 0 then
            saveLevelProgress(currentLevel, true, hasMedalForLevel())
        end
        -- Used for animating level complete banner
        if levelCompleteTimer < LEVEL_COMPLETE_TIMER_MAX then
            levelCompleteTimer = levelCompleteTimer + 1
        end
        if currentLevel < #LEVELS and levelTransitionTimer == 0 then
            if btnp(5) then
                levelTransitionTimer = LEVEL_TRANSITION_TIMER_MAX
                levelTransitionCallback = (function ()
                    currentLevel = currentLevel + 1
                    resetLevel(currentLevel)
                end)
            elseif btnp(4) then
                levelTransitionTimer = LEVEL_TRANSITION_TIMER_MAX
                levelTransitionCallback = (function ()
                    state = STATES.SELECT
                    initSelect()
                end)
            end
        end
    end

    if player.shownSign and shownSignTimer < SHOWN_SIGN_TIMER_MAX then
        shownSignTimer = shownSignTimer + 1
    elseif not player.shownSign and shownSignTimer > 0 then
        shownSignTimer = shownSignTimer - 1
    end

    foreach(locks, updateSelf)
    foreach(entities, updateSelf)
    foreach(bullets, function(bullet)
        if bullet.isDestroyed then
            del(bullets, bullet)
        else
            bullet:update()
        end
    end)

    if cameraShake > 0 then
        cameraShake = cameraShake - 0.1
    else
        cameraShake = 0
    end

    if #bullets == 0 and player.bullets == 0 and levelTransitionTimer == 0 then
        levelTransitionTimer = LEVEL_TRANSITION_TIMER_MAX
    end
end

function drawSelf(self)
    self:draw()
end


function drawHudText(text, x, y)
    print(text, x, y + 1, 5)
    print(text, x, y, 7)
end


local LEVEL_COMPLETE_TEXT = 'level complete'
local NEXT_LEVEL_TEXT = '\x97 next level'
local BACK_TO_SELECT_TEXT = '\x8e return to level select'
function drawHud()
    drawHudText('Lev. '..tostr(currentLevel), 8, 14 * 8 + 5)
    palt(14, true)
    palt(0, false)
    spr(35, 40, 14 * 8 + 4)
    spr(36, 72, 14 * 8 + 4)
    palt(14, false)
    palt(0, true)
    drawHudText('x'..tostr(player.bullets), 52, 14 * 8 + 5)
    local medalBullets = LEVELS[currentLevel].medalBullets - (LEVELS[currentLevel].maxBullets - player.bullets)
    local medalText = 'x'..tostr(medalBullets)
    if medalBullets <= 0 then
        medalText = '-'
    end
    drawHudText(medalText, 84, 14 * 8 + 5)

    clip(0, 14 * 8, 128, 16 * shownSignTimer/SHOWN_SIGN_TIMER_MAX)
    rectfill(1, 14 * 8 + 1, 126, 16 * 8 - 2, 0)
    if player.shownSign then
        -- TODO proper two line text.
        print(player.shownSign.text[1], 3, 14 * 8 + 3, 7)
        print(player.shownSign.text[2], 3, 14 * 8 + 9, 7)
    end
    clip()

    -- Show animated level complete banner...if level is complete.
    if isLevelComplete() then
        local bannerClipProgress = levelCompleteTimer/LEVEL_COMPLETE_TIMER_MAX
        clip(0, 59, 128, 40 * bannerClipProgress)
        rectfill(0, 59, 127, 69, 0)
        local levelCompleteColor = 7
        -- TODO different colour if medal
        printCentre(LEVEL_COMPLETE_TEXT, 62, levelCompleteColor)

        rectfill(0, 72, 127, 95, 0)
        printCentre(NEXT_LEVEL_TEXT, 78, 7)
        printCentre(BACK_TO_SELECT_TEXT, 86, 7)
        clip()
    end
end

function drawTransition()
    -- Draw concentric circles of different fill gradients to give
    -- illusion of fading circle edge.
    if levelTransitionTimer > 0 then
        local radiusRatio = ((LEVEL_TRANSITION_TIMER_MAX/2) - abs(levelTransitionTimer - LEVEL_TRANSITION_TIMER_MAX/2))/(LEVEL_TRANSITION_TIMER_MAX/2)
        local radius = 128 * radiusRatio
        fillp('0b0111111101111111.1')
        circfill(64, 64, radius, 7)
        if radius > 8 then
            fillp('0b1101101111011011.1')
            circfill(64, 64, radius - 8, 7)
        end
        if radius > 16 then
            fillp('0b0101101001011010.1')
            circfill(64, 64, radius - 16, 7)
        end
        if radius > 24 then
            fillp('0b0001100000011000.1')
            circfill(64, 64, radius - 24, 7)
        end
        if radius > 32 then
            fillp()
            circfill(64, 64, radius - 32, 7)
        end
        fillp()
    end
end

function drawGame()
    cls()
    camera(cameraShake * (rnd(4) - 2), cameraShake * (rnd(4) - 2))
    map(0, 0, 0, 0, 16, 16)
    -- special case to superimpose arrows on level for first level
    if currentLevel == 1 then
        print('\x8b', 2 * 8 - 3, 12 * 8 + 1, 7)
        print('\x91', 4 * 8 + 5, 12 * 8 + 1, 7)
    end
    foreach(entities, drawSelf)
    foreach(switches, drawSelf)
    foreach(locks, drawSelf)
    foreach(bullets, drawSelf)
    player:draw()
    camera()
    drawHud()
end

function initTitle()
    bumpWorld = bump.newWorld(8)
    entities = {}
    bullets = {}
    add(entities, Wall(-32, -32, 8, 192))
    add(entities, Wall(-32, -32, 192, 8))
    add(entities, Wall(160, -32, 8, 192))
    add(entities, Wall(160, 160, 192, 8))
    add(entities, Wall(24, 48, 80, 32))
end

function updateTitle()
    if btnp(5) and titleTimer > TITLE_TIMER_MAX then
        levelTransitionTimer = LEVEL_TRANSITION_TIMER_MAX
        levelTransitionCallback = (function ()
            state = STATES.SELECT
            initSelect()
        end)
    end
    if rnd() < 0.01 then
        local side = rnd()
        local bulletX, bulletY
        if side < 0.25 then
            -- left
            bulletX = -16
            bulletY = -16 + rnd(160)
        elseif side < 0.5 then
            -- right
            bulletX = 144
            bulletY = -16 + rnd(160)
        elseif side < 0.75 then
            -- top
            bulletX = -16 + rnd(160)
            bulletY = -16
        else
            --bottom
            bulletX = -16 + rnd(160)
            bulletY = 144
        end
        add(bullets, Bullet(bulletX, bulletY, rnd()))
    end
    foreach(bullets, function(bullet)
        if bullet.isDestroyed then
            del(bullets, bullet)
        else
            bullet:update()
        end
    end)
end

local pressStartText = 'press \x97 to play'
local pressStartColors = { 0, 5, 6, 7, 6, 5, 0 }
function drawTitle()
    cls()
    map(0, 16, 0, 0, 16, 16)
    spr(80, 24, 6.5 * 8, 10, 3)
    foreach(bullets, drawSelf)
    foreach(entities, drawSelf)

    local textColor = pressStartColors[flr(titleTimer/8) % #pressStartColors + 1]
    printCentre(pressStartText, 11 * 8, textColor)
end

local SELECT_TIMER_MAX = 240
local cursorX
local cursorY
local selectTimer
local selectWidth = 6
function initSelect()
    cursorX = 0
    cursorY = 0
    selectTimer = 0
end

function updateSelect()
    selectTimer = (selectTimer + 1) % SELECT_TIMER_MAX
    if btnp(0) then
        cursorX = cursorX - 1
    elseif btnp(1) then
        cursorX = cursorX + 1
    elseif btnp(2) then
        cursorY = cursorY - 1
    elseif btnp(3) then
        cursorY = cursorY + 1
    end
    cursorX = cursorX % selectWidth
    cursorY = cursorY % selectWidth

    if btnp(5) or btnp(4) then
        levelTransitionTimer = LEVEL_TRANSITION_TIMER_MAX
        levelTransitionCallback = (function ()
            state = STATES.GAME
            initGame(cursorY * selectWidth + cursorX + 1)
        end)
    end
end

function drawLevelIcon(x, y, levelNumber, isSelected, isComplete, hasMedal)
    levelNumber = tostr(levelNumber)
    local iconColor = 5
    if hasMedal then
        iconColor = 9
    elseif isComplete then
        iconColor = 13
    end
    rectfill(x, y, x + 15, y + 15, iconColor)
    local iconFrameColor = 0
    if isSelected then
        iconFrameColor = 7
    end
    rect(x, y, x + 15, y + 15, iconFrameColor)
    print(levelNumber, x + (16 - #levelNumber * 4)/2, y + 7, 0)
    print(levelNumber, x + (16 - #levelNumber * 4)/2, y + 6, 7)
end

local LEVEL_SELECT_TEXT = 'select level'
function drawSelect()
    cls()
    camera(0, selectTimer/SELECT_TIMER_MAX * 128)
    map(16, 0, 0, 0)
    camera()
    printCentre(LEVEL_SELECT_TEXT, 8, 7)
    for x=0,selectWidth - 1 do
        for y=0,selectWidth - 1 do
            local levelNumber = y * selectWidth + x + 1
            local isComplete, hasMedal = loadLevelProgress(levelNumber)
            drawLevelIcon(
                12 + x * 18,
                16 + y * 18,
                levelNumber,
                x == cursorX and y == cursorY,
                isComplete,
                hasMedal
            )
        end
    end
end

function _init()
    -- Disable button repeating
    poke(0x5f5c, 255)
    cartdata('propulsion')

    titleTimer = 0
    levelTransitionTimer = LEVEL_TRANSITION_TIMER_MAX/2

    state = STATES.TITLE
    initTitle()
end

function _update60()
    if state == STATES.GAME then
        updateGame()
    elseif state == STATES.TITLE then
        updateTitle()
    elseif state == STATES.SELECT then
        updateSelect()
    end

    titleTimer = titleTimer + 1
    if titleTimer > TITLE_TIMER_MAX and levelTransitionTimer > 0 then
        levelTransitionTimer = levelTransitionTimer - 1
        if levelTransitionTimer == LEVEL_TRANSITION_TIMER_MAX/2 then
            if levelTransitionCallback then
                levelTransitionCallback()
                levelTransitionCallback = nil
            end
        end
    end
end

function _draw()
    if state == STATES.GAME then
        drawGame()
    elseif state == STATES.TITLE then
        drawTitle()
    elseif state == STATES.SELECT then
        drawSelect()
    end
    drawTransition()

    if titleTimer < TITLE_TIMER_MAX then
        local textColor = 0
        if titleTimer > TITLE_TIMER_MAX - 16 or titleTimer < 8 then
            textColor = 7
        elseif titleTimer > TITLE_TIMER_MAX - 20 or titleTimer < 12 then
            textColor = 6
        elseif titleTimer > TITLE_TIMER_MAX - 24 or titleTimer < 16 then
            textColor = 5
        end
        print('ruairidx', 50, 61, textColor)
    end
end
-- END MAIN
