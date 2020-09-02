local bumpWorld
local entities
local bullets
local cameraShake
local GRAVITY = 0.25

local Entity = Object:extend()

function Entity:new(x, y, width, height)
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    bumpWorld:add(self, self.x, self.y, self.width, self.height)
end

function Entity:getPlayerCollisionType()
    return 'slide'
end

function Entity:getBulletCollisionType()
    return 'slide'
end

function Entity:update()
    --
end

function Entity:draw()
    --
end

function Entity:destroy()
    bumpWorld:remove(self, self.y, self.y, self.width, self.height)
end

local Wall = Entity:extend()

function Wall:draw()
    rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 7)
end

local Bullet = Entity:extend()
Bullet.SPEED = 2

function Bullet:new(x, y, angle)
    Bullet.super.new(self, x, y, 4, 4)
    self.velX = cos(angle)
    self.velY = sin(angle)
    self.bounces = 0
    self.lastPositions = {}
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
    end
    add(self.lastPositions, { x = self.x, y = self.y })
    while #self.lastPositions > 4 do
        del(self.lastPositions, self.lastPositions[1])
    end
end

function Bullet:draw()
    for i=1,4 do
        if i <= #self.lastPositions then
            local lastPosition = self.lastPositions[#self.lastPositions - i + 1]
            circfill(
                lastPosition.x + 2,
                lastPosition.y + 2,
                self.width/4,
                flr(rnd(16))
            )
        end
    end
    circfill(
        self.x + 2,
        self.y + 2,
        self.width/2,
        flr(rnd(16))
    )
end

local Player = Entity:extend()
Player.SPEED = 1

function Player:new(x, y)
    Player.super.new(self, x, y, 8, 8)
    self.velY = 0
    self.onGround = false
    self.angle = 0
    self.changingAngle = false
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

    if self.changingAngle then
        if btn(0) then
            self.angle = self.angle + 0.01
        elseif btn(1) then
            self.angle = self.angle - 0.01
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
            self.velY = -4
        end
    end

    if btnp(5) then
        self.changingAngle = not self.changingAngle
    end

    if btnp(4) then
        add(bullets, Bullet(self.x + 3, self.y + 3, self.angle))
        cameraShake = 1
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
        end
    end
end

function Player:draw()
    rectfill(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, 4)
    line(
        self.x + 4,
        self.y + 4,
        self.x + 4 + 16 * cos(self.angle),
        self.y + 4 + 16 * sin(self.angle),
        8
    )
end

-- START MAIN
local player

function _init()
    -- Disable button repeating
    poke(0x5f5c, 255)
    bumpWorld = bump.newWorld(8)
    player = Player(32, 32)
    entities = {}
    add(entities, Wall(16, 48, 32, 8))
    add(entities, Wall(8, 80, 80, 8))
    add(entities, Wall(64, 0, 8, 80))
    bullets = {}
    cameraShake = 0
end

function _update()
    player:update()
    for entity in all(entities) do
        entity:update()
    end
    for bullet in all(bullets) do
        bullet:update()
    end
    if cameraShake > 0 then
        cameraShake = cameraShake - 0.1
    else
        cameraShake = 0
    end
end

function _draw()
    cls()
    camera(cameraShake * (rnd(4) - 2), cameraShake * (rnd(4) - 2))
    for entity in all(entities) do
        entity:draw()
    end
    for bullet in all(bullets) do
        bullet:draw()
    end
    player:draw()
end
-- END MAIN
