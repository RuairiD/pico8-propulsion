VERSION = 'v1.0.0'
LEVEL_WIDTH = 16
LEVEL_HEIGHT = 14
GRAVITY = 0.125
LEVEL_TRANSITION_TIMER_MAX = 60
LEVEL_TRANSITION_TIMER_MAX_HALF = 30
SHOWN_SIGN_TIMER_MAX = 10
LEVEL_COMPLETE_TIMER_MAX = 30

STATES = {
    INTRO = 'INTRO',
    TITLE = 'TITLE',
    GAME = 'GAME',
    SELECT = 'SELECT',
}

function setPinkTransparent()
    palt(14, true)
    palt(0, false)
end


function setBlackTransparent()
    palt(14, false)
    palt(0, true)
end

function printCentre(text, y, color)
    print(text, (128 - #text * 4)/2, y, color)
end

function loadLevelProgress(levelNumber)
    local data = dget(levelNumber - 1)
    local isComplete = (data & 1) == 1
    local hasMedal = (data & 2) == 2
    return isComplete, hasMedal
end

function saveLevelProgress(levelNumber, isComplete, hasMedal)
    -- Careful not to overwrite existing data; if the player already has a medal,
    -- missing it on a retry shouldn't remove it.
    local existingIsComplete, existingHasMedal = loadLevelProgress(levelNumber)
    local data = 0
    if isComplete or existingIsComplete then
        data = data | 1
    end
    if hasMedal or existingHasMedal then
        data = data | 2
    end
    dset(levelNumber - 1, data)
end

function startTransition(callback)
    levelTransitionTimer = LEVEL_TRANSITION_TIMER_MAX
    levelTransitionCallback = callback
end

Entity = Object:extend()

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


SWITCH_COLORS = {
    RED = 8,
    GREEN = 11,
    BLUE = 12,
}

Switch = Entity:extend()

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

Lock = Entity:extend()

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


Sign = Entity:extend()
Sign.TOOLTIP = 'hold \x83 to read'

function Sign:new(x, y, text)
    Switch.super.new(self, x, y, 8, 8)
    self.text = text
end

function Sign:draw()
    setPinkTransparent()
    spr(13, self.x, self.y)
    setBlackTransparent()
    -- Fuzzy screen
    fillp(flr(rnd(0x8000)))
    rectfill(self.x + 1, self.y + 1, self.x + 6, self.y + 4, 11)
    fillp()

    -- Show tooltip
    if player.shownSign == self then
        local tooltipX = self.x + (8 - #Sign.TOOLTIP * 4)/2
        if tooltipX < 2 then
            tooltipX = 2
        end
        rectfill(tooltipX - 1, self.y - 15, tooltipX + #Sign.TOOLTIP * 4 + 3, self.y - 9, 0)
        print(Sign.TOOLTIP, tooltipX, self.y - 14, 7)
    end
end

function Sign:getPlayerCollisionType()
    return 'cross'
end

function Sign:getBulletCollisionType()
    return nil
end


Wall = Entity:extend()

function Wall:draw()
    -- rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 7)
end

Platform = Wall:extend()
-- rest is below Player

Fence = Wall:extend()

function Fence:getBulletCollisionType()
    return nil
end

function Fence:draw()
    fillp('0b0101101001011010.1')
    rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 6)
    fillp()
end


SwitchWall = Wall:extend()
SwitchWall.FILL_PATTERNS = {
    '0b1111000000000000.1',
    '0b0000111100000000.1',
    '0b0000000011110000.1',
    '0b0000000000001111.1',
}

SwitchWall.FADE_TIMER_MAX = 6

function SwitchWall:new(x, y, width, height, color)
    SwitchWall.super.new(self, x, y, width, height)
    self.color = color
    self.fillPatternIndex = 0
    self.fadeTimer = SwitchWall.FADE_TIMER_MAX
end

function SwitchWall:update()
    self.fillPatternIndex = self.fillPatternIndex + 1
    if self:isDisabled() and self.fadeTimer > 0 then
        self.fadeTimer = self.fadeTimer - 1
    end
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
    if self.fadeTimer > 0 then
        fillp(SwitchWall.FILL_PATTERNS[self.fillPatternIndex % #SwitchWall.FILL_PATTERNS + 1])
        rectfill(self.x, self.y, self.x + self.width - 1, self.y + flr(self.height * self.fadeTimer/SwitchWall.FADE_TIMER_MAX) - 1, self.color)
        fillp()
    end
end


Bullet = Entity:extend()
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
Bullet.MAX_LIFE = (256/Bullet.SPEED) * Bullet.MAX_BOUNCES + Bullet.DEATH_TIMER_MAX

function Bullet:new(x, y, angle, isTitleScreen)
    Bullet.super.new(self, x, y, 4, 4)
    self.velX = cos(angle)
    self.velY = sin(angle)
    self.bounces = 0
    self.lastPositions = {}
    self.deathTimer = 0
    self.timeAlive = 0
    -- Used to control bounce sound.
    self.isTitleScreen = isTitleScreen
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
                if not self.isTitleScreen then
                    sfx(58)
                end
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
                sfx(62)
                sfx(55)
            end
            if collision.other:is(Lock) and not collision.other.isDisabled then
                sfx(57)
                collision.other.isDisabled = true
            end
        end
        -- Keep track of previous positions for a trail effect, but no more than necessary.
        add(self.lastPositions, { x = self.x, y = self.y })
        while #self.lastPositions > Bullet.TRAIL_LENGTH do
            del(self.lastPositions, self.lastPositions[1])
        end
    else
        if not self.isTitleScreen and self.deathTimer == 0 then
            sfx(61)
        end
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

Player = Entity:extend()
Player.SPEED = 1

function Player:new(x, y, bullets)
    Player.super.new(self, x, y, 8, 8)
    self.bullets = bullets
    self.velY = 0
    self.walkFrame = 0
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
            self.walkFrame = self.walkFrame + 1
        elseif btn(1) then
            goalX = goalX + Player.SPEED
            self.walkFrame = self.walkFrame + 1
        else
            self.walkFrame = 0
        end
        self.walkFrame = self.walkFrame % 12
    end

    if btnp(2) then
        if self.onGround then
            sfx(56)
            self.velY = -2.5
        end
    end

    if btnp(4) and self.bullets > 0 then
        -- Start bullet a little ahead of centre
        add(bullets, Bullet(
            self.x + 2 + 4 * cos(self.angle),
            self.y + 2 + 4 * sin(self.angle),
            self.angle
        ))
        cameraShake = 1
        self.bullets = self.bullets - 1
        sfx(59)
        sfx(60)
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

    self.shownSign = nil
    for _, collision in ipairs(collisions) do
        if collision.other:is(Wall) then
            if collision.normal.y == 1 then
                -- Player has bonked wall above.
                self.velY = 0
            elseif collision.normal.y == -1 then
                -- Player has landed!
                self.onGround = true
                self.velY = 0

                if collision.other:is(Platform) then
                    self.x, self.y, _, _ = bumpWorld:move(
                        self,
                        self.x + collision.other.velX * collision.other.direction,
                        self.y + collision.other.velY * collision.other.direction,
                        self.moveFilter
                    )
                    -- non-zero velY is a hack to push player down into floor on every frame,
                    -- ensuring accurate collision reporting (e.g. no skipped collisions where
                    -- player is just about hovering above)
                    self.velY = GRAVITY
                end
            end
        elseif collision.other:is(Sign) then
            self.shownSign = collision.other
        end
    end
end

LINE_BUFFER = 10
LINE_LENGTH = 64
function Player:draw()
    setPinkTransparent()
    local movingLeft = self.angle > 0.25 and self.angle < 0.75
    if self.onGround then
        spr(128 + flr(self.walkFrame / 3), self.x, self.y - 8, 1, 2, movingLeft)
    else
        if self.velY < 0 then
            spr(132, self.x, self.y - 8, 1, 2, movingLeft)
        else
            spr(133, self.x, self.y - 8, 1, 2, movingLeft)
        end
    end
    setBlackTransparent()
    local lineColorCode = 7
    if btn(5) then
        lineColorCode = 10
    end
    local cosAngle = cos(self.angle)
    local sinAngle = sin(self.angle)
    line(
        self.x + 4 + LINE_BUFFER * cosAngle,
        self.y + 4 + LINE_BUFFER * sinAngle,
        self.x + 4 + LINE_LENGTH * cosAngle,
        self.y + 4 + LINE_LENGTH * sinAngle,
        lineColorCode
    )
end


function Platform:new(x, y, width, height, isVertical, minPos, maxPos)
    Platform.super.new(self, x, y, width, height)
    self.isVertical = isVertical
    self.velX = 0
    self.velY = 0
    if self.isVertical then
        self.velY = 1
    else
        self.velX = 1
    end
    self.minPos = minPos
    self.maxPos = maxPos
    self.direction = 1
    self.frame = 0
end

function Platform:update()
    self.frame = self.frame + 1
    self.x = self.x + self.velX * self.direction
    self.y = self.y + self.velY * self.direction
    if self.isVertical then
        if self.y <= self.minPos or self.y >= self.maxPos then
            self.direction = self.direction * -1
        end
    else
        if self.x <= self.minPos or self.x >= self.maxPos then
            self.direction = self.direction * -1
        end
    end
    self.x, self.y, _, _ = bumpWorld:move(self, self.x, self.y, function (self, other)
        if other:is(Player) or (other:is(SwitchWall) and not other:isDisabled()) then
            return 'slide'
        end
        return nil
    end)
end

function Platform:draw()
    local spriteIndex = 67
    if flr(self.frame / 30) % 2 == 0 then
        spriteIndex = 68
    end
    for xi=0, self.width - 1, 8 do
        for yi=0, self.height - 1, 8 do
            spr(spriteIndex, self.x + xi, self.y + yi)
        end
    end
end

function getActiveGates()
    local count = 0
    for lock in all(locks) do
        if not lock.isDisabled then
            count = count + 1
        end
    end
    return count
end

function isLevelComplete()
    return getActiveGates() == 0
end

function hasMedalForLevel()
    return isLevelComplete() and (LEVELS[currentLevel].maxBullets - player.bullets) <= LEVELS[currentLevel].medalBullets
end

function resetLevel(levelNumber)
    local levelData = LEVELS[levelNumber]
    showingText = false
    bumpWorld = bump.newWorld(8)
    entities, switches, locks, bullets = {}, {}, {}, {}
    for y=0, LEVEL_HEIGHT - 1 do
        for x=0, LEVEL_WIDTH - 1 do
            local tileIndex = 2 * (y * LEVEL_WIDTH + x) + 1
            local tile = tonum("0x"..sub(levelData.tiles, tileIndex, tileIndex + 1))
            mset(x, y, tile)
        end
    end
    local entitiesData = levelData.entities
    for i=1,#levelData.entities - 1,3 do
        local pos, props = entitiesData[i + 1], entitiesData[i + 2]
        pos = split(pos)
        local x, y, width, height = tonum(pos[1]), tonum(pos[2]), tonum(pos[3]), tonum(pos[4])
        if entitiesData[i] == "SPAWN" then
            player = Player(x, y, levelData.maxBullets)
        elseif entitiesData[i] == "LOCK" then
            add(locks, Lock(x, y))
        elseif entitiesData[i] == "SWITCH" then
            add(switches, Switch(x, y, SWITCH_COLORS[props.color]))
        elseif entitiesData[i] == "SWITCH_WALL" then
            add(entities, SwitchWall(x, y, width, height, SWITCH_COLORS[props.color]))
        elseif entitiesData[i] == "FENCE" then
            add(entities, Fence(x, y, width, height))
        elseif entitiesData[i] == "PLATFORM" then
            add(entities, Platform(x, y, width, height, props.isVertical == "true", tonum(props.minPos), tonum(props.maxPos)))
        elseif entitiesData[i] == "SIGN" then
            add(entities, Sign(
                x, y,
                props.text
            ))
        end
    end
    -- Add border walls
    add(entities, Wall(0, 0, 128, 8))
    add(entities, Wall(0, 0, 8, 128))
    add(entities, Wall(0, 104, 128, 8))
    add(entities, Wall(120, 0, 8, 128))
    local wallDimensions = split(levelData.walls)
    -- #wallDimensions - 1 to account for trailing comma
    for i=1, #wallDimensions - 1, 4 do
        add(entities, Wall(
            tonum(wallDimensions[i]),
            tonum(wallDimensions[i + 1]),
            tonum(wallDimensions[i + 2]),
            tonum(wallDimensions[i + 3])
        ))
    end
end

function initGame(initLevel)
    cameraShake = 0
    currentLevel = initLevel or 1
    resetLevel(currentLevel)
    menuitem(1, "reset level", (function ()
        startTransition(function ()
            resetLevel(currentLevel)
        end)
    end))
    menuitem(2, "level select", (function ()
        startTransition(function ()
            state = STATES.SELECT
            initSelect()
        end)
    end))
end

function updateSelf(self)
    self:update()
end

function updateGame()
    if not isLevelComplete() then
        if not showingText then
            player:update()
        end
        levelCompleteTimer = 0
        showingText = player.shownSign ~= nil and btn(3)

        -- Reset level
        if #bullets == 0 and player.bullets == 0 and levelTransitionTimer == 0 then
            startTransition(function ()
                resetLevel(currentLevel)
            end)
        end
    else
        showingText = false
        if levelCompleteTimer == 0 then
            if currentLevel == #LEVELS then
                sfx(54)
            end
            saveLevelProgress(currentLevel, true, hasMedalForLevel())
        end
        -- Used for animating level complete banner
        if levelCompleteTimer < LEVEL_COMPLETE_TIMER_MAX then
            levelCompleteTimer = levelCompleteTimer + 1
        end
        if levelTransitionTimer == 0 then
            if btnp(5) and currentLevel < #LEVELS then
                sfx(63)
                startTransition(function ()
                    currentLevel = currentLevel + 1
                    resetLevel(currentLevel)
                end)
            elseif btnp(4) then
                sfx(63)
                startTransition(function ()
                    state = STATES.SELECT
                    initSelect()
                end)
            end
        end
    end

    if not showingText then
        foreach(locks, updateSelf)
        foreach(entities, updateSelf)
        foreach(bullets, function(bullet)
            if bullet.isDestroyed then
                del(bullets, bullet)
            else
                bullet:update()
            end
        end)
    end

    if cameraShake > 0 then
        cameraShake = cameraShake - 0.1
    else
        cameraShake = 0
    end
end

function drawSelf(self)
    self:draw()
end


function drawHudText(text, x, y)
    print(text, x, y + 1, 0)
    print(text, x, y, 7)
end

SIGN_LINE_LENGTH = 92
function drawSignText(text)
    local words = split(text, ' ')
    local line = ''
    local y = 33
    for word in all(words) do
        if #(line..word) * 4 < SIGN_LINE_LENGTH then
            line = line..word.." "
        else
            print(line, 17, y, 11)
            line = word.." "
            y = y + 8
        end
    end
    print(line, 17, y, 11)
end


MEDAL_GET_TEXT = 'medal get!'
LEVEL_COMPLETE_TEXT = 'level complete'
ESCAPE_COMPLETE_TEXT = 'escape complete'
NEXT_LEVEL_TEXT = '\x97 next level'
BACK_TO_SELECT_TEXT = '\x8e return to level select'
function drawHud()
    drawHudText('Lev. '..tostr(currentLevel), 8, 117)
    setPinkTransparent()
    spr(35, 40, 116)
    spr(36, 68, 116)
    setBlackTransparent()
    spr(29, 96, 116)
    drawHudText('x'..tostr(player.bullets), 52, 117)
    local medalBullets = LEVELS[currentLevel].medalBullets - (LEVELS[currentLevel].maxBullets - player.bullets)
    local medalText = 'x'..tostr(medalBullets)
    if medalBullets <= 0 then
        medalText = '-'
    end
    drawHudText(medalText, 80, 117)
    drawHudText('x'..tostr(getActiveGates()), 108, 117)

    if showingText then
        rectfill(14, 14, 113, 97, 11)
        rectfill(15, 15, 112, 96, 0)
        printCentre('info', 20, 11)
        drawSignText(player.shownSign.text)
    end

    -- Show animated level complete banner...if level is complete.
    if isLevelComplete() then
        local bannerClipProgress = levelCompleteTimer/LEVEL_COMPLETE_TIMER_MAX
        local isLastLevel = currentLevel == #LEVELS

        if isLastLevel then
            -- show shaft of light
            clip(108 - 12 * bannerClipProgress, 0, 24 * bannerClipProgress, 128)
            fillp('0b0111111111011111.1')
            rectfill(0, 20, 127, 25, 7)
            fillp('0b0111110101111101.1')
            rectfill(0, 14, 127, 19, 7)
            fillp('0b0101101001011010.1')
            rectfill(0, 8, 127, 13, 7)
            fillp()
            rectfill(0, 0, 127, 7, 7)
            clip()
        end

        clip(0, 47, 128, 60 * bannerClipProgress)
        rectfill(0, 47, 127, 57, 0)
        if hasMedalForLevel() then
            rectfill(0, 59, 127, 69, 0)
            printCentre(MEDAL_GET_TEXT, 62, 10)
        end

        if not isLastLevel then
            printCentre(LEVEL_COMPLETE_TEXT, 50, 7)
            rectfill(0, 72, 127, 95, 0)
            printCentre(NEXT_LEVEL_TEXT, 78, 7)
            printCentre(BACK_TO_SELECT_TEXT, 86, 7)
        else
            printCentre(ESCAPE_COMPLETE_TEXT, 50, 7)
            rectfill(0, 72, 127, 87, 0)
            printCentre(BACK_TO_SELECT_TEXT, 78, 7)
        end
        clip()
    end
end

function drawTransition()
    -- Draw concentric circles of different fill gradients to give
    -- illusion of fading circle edge.
    if levelTransitionTimer > 0 then
        radiusRatio = (LEVEL_TRANSITION_TIMER_MAX_HALF - abs(levelTransitionTimer - LEVEL_TRANSITION_TIMER_MAX_HALF))/LEVEL_TRANSITION_TIMER_MAX_HALF
        radius = 128 * radiusRatio
        fillp('0b0111111101111111.1')
        circfill(64, 64, radius, 0)
        if radius > 8 then
            fillp('0b1101101111011011.1')
            circfill(64, 64, radius - 8, 0)
        end
        if radius > 16 then
            fillp('0b0101101001011010.1')
            circfill(64, 64, radius - 16, 0)
        end
        if radius > 24 then
            fillp('0b0001100000011000.1')
            circfill(64, 64, radius - 24, 0)
        end
        if radius > 32 then
            fillp()
            circfill(64, 64, radius - 32, 0)
        end
        fillp()
    end
end

function drawGame()
    camera(cameraShake * (rnd(4) - 2), cameraShake * (rnd(4) - 2))
    map(0, 0, 0, 0, 16, 16)
    -- special case to superimpose arrows on level for first level
    if currentLevel == 1 then
        print('\x8b', 13, 97, 7)
        print('\x91', 37, 97, 7)

        spr(134, 36, 84)
        print('you', 46, 80, 7)
        spr(135, 60, 28)
        print('shoot', 54, 40, 7)
        print('this', 56, 46, 7)
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
    titleTimer = 0
end

function updateTitle()
    titleTimer = titleTimer + 1
    if levelTransitionTimer == 0 and btnp(5) then
        sfx(63)
        startTransition(function ()
            state = STATES.SELECT
            initSelect()
        end)
    end
    if #bullets < 4 and rnd() < 0.1 then
        local side = rnd()
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
        add(bullets, Bullet(bulletX, bulletY, rnd(), true))
    end
    foreach(bullets, function(bullet)
        if bullet.isDestroyed then
            del(bullets, bullet)
        else
            bullet:update()
        end
    end)
end

pressStartText = 'press \x97 to play'
pressStartColors = { 0, 5, 6, 7, 6, 5, 0 }
function drawTitle()
    map(0, 16, 0, 0, 16, 16)
    spr(80, 24, 52, 10, 3)
    foreach(bullets, drawSelf)
    foreach(entities, drawSelf)

    local textColor = pressStartColors[flr(titleTimer/8) % #pressStartColors + 1]
    printCentre(pressStartText, 88, textColor)

    printCentre(VERSION, 122, 0)
    printCentre(VERSION, 121, 7)
end

SELECT_TIMER_MAX = 240
cursorX = 0
cursorY = 0
selectWidth = 5

function initSelect()
    selectTimer = 0
    menuitem(2)
    menuitem(1)
end

function updateSelect()
    selectTimer = (selectTimer + 1) % SELECT_TIMER_MAX
    if levelTransitionTimer == 0 then
        if btnp(0) then
            cursorX = cursorX - 1
            sfx(62)
        elseif btnp(1) then
            cursorX = cursorX + 1
            sfx(62)
        elseif btnp(2) then
            cursorY = cursorY - 1
            sfx(62)
        elseif btnp(3) then
            cursorY = cursorY + 1
            sfx(62)
        end
        if cursorX >= selectWidth then
            cursorY = cursorY + 1
        elseif cursorX < 0 then
            cursorY = cursorY - 1
        end
        cursorX = cursorX % selectWidth
        cursorY = cursorY % selectWidth

        if (btnp(5) or btnp(4)) then
            sfx(63)
            startTransition(function ()
                state = STATES.GAME
                initGame(cursorY * selectWidth + cursorX + 1)
            end)
        end
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

LEVEL_SELECT_TEXT = 'select level'
function drawSelect()
    camera(0, selectTimer/SELECT_TIMER_MAX * 128)
    map(16, 0, 0, 0)
    camera()
    printCentre(LEVEL_SELECT_TEXT, 8, 7)
    for x=0, selectWidth - 1 do
        for y=0, selectWidth - 1 do
            local levelNumber = y * selectWidth + x + 1
            local isComplete, hasMedal = loadLevelProgress(levelNumber)
            drawLevelIcon(
                21 + x * 18,
                24 + y * 18,
                levelNumber,
                x == cursorX and y == cursorY,
                isComplete,
                hasMedal
            )
        end
    end
end

introTimer = 0
LOGO_TIMER_MAX = 120
INTRO_TIMER_MAX = 300
STORY_TIMER_MAX = INTRO_TIMER_MAX - LOGO_TIMER_MAX

function updateIntro()
    introTimer = introTimer + 1
    if levelTransitionTimer == 0 and introTimer >= INTRO_TIMER_MAX or btnp(5) or btnp(4) then
        startTransition(function ()
            state = STATES.TITLE
            initTitle()
        end)
    end
end

introColors = { 0, 5, 6, 7 }
function drawIntro()
    if introTimer < LOGO_TIMER_MAX then
        introIndex = introTimer
        if introTimer < LOGO_TIMER_MAX - 16 and introTimer > 16 then
            introIndex = 16
        elseif introTimer >= LOGO_TIMER_MAX - 16 then
            introIndex = LOGO_TIMER_MAX - introTimer
        end

        textColor = introColors[ceil(introIndex/4)]
        printCentre('ruairidx', 61, textColor)
    elseif introTimer < INTRO_TIMER_MAX then
        storyTimer = introTimer - LOGO_TIMER_MAX
        
        introIndex = storyTimer
        if storyTimer < STORY_TIMER_MAX - 16 and storyTimer > 16 then
            introIndex = 16
        elseif storyTimer >= STORY_TIMER_MAX - 16 then
            introIndex = STORY_TIMER_MAX - storyTimer
        end

        textColor = introColors[ceil(introIndex/4)]
        printCentre('imprisoned beneath', 16, textColor)
        printCentre('the earth...', 24, textColor)
        printCentre('only your wit, guile and', 48, textColor)
        printCentre('a plasma pistol for company', 56, textColor)
        clip(0, 68, 128, introIndex)
        setPinkTransparent()
        spr(128 + flr(introTimer/4) % 4, 60, 68, 1, 2)
        setBlackTransparent()
        clip()
        printCentre('however will you escape?', 96, textColor)
    end
end

function _init()
    -- Disable button repeating
    poke(0x5f5c, 255)
    cartdata('ruairidx_propulsion_1')
    music(0, 2000)
    levelTransitionTimer = 0

    state = STATES.INTRO

    -- poke(0x5f2f, 1)
end

updateFunctions = {
    GAME = updateGame,
    TITLE = updateTitle,
    SELECT = updateSelect,
    INTRO = updateIntro,
}
function _update60()
    updateFunctions[state]()

    if levelTransitionTimer > 0 then
        levelTransitionTimer = levelTransitionTimer - 1
        if levelTransitionTimer == LEVEL_TRANSITION_TIMER_MAX_HALF then
            if levelTransitionCallback then
                levelTransitionCallback()
                levelTransitionCallback = nil
            end
        end
    end
end

drawFunctions = {
    GAME = drawGame,
    TITLE = drawTitle,
    SELECT = drawSelect,
    INTRO = drawIntro,
}
function _draw()
    cls()
    drawFunctions[state]()
    drawTransition()
end
-- END MAIN
