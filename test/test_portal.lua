local navigation = require "navigation"
local w = 20
local h = 20
local nav = navigation.new(w, h, {
    -- {1, 0},
})

for y = 0, h - 1 do
    nav:set_obstacle { x = 5, y = y }
    nav:set_obstacle { x = 6, y = y }
    nav:set_obstacle { x = 7, y = y }
end

local portal_pos = { x = 6, y = 6 }

local joints = {
    { x = 4, y = 6 },
    { x = 8, y = 6 },
}

for _, pos in pairs(joints) do
    nav:set_obstacle(pos)
end

nav:update_areas()
nav.core:dump()
nav.core:dump_connected()

nav:add_portal(portal_pos, nil, nil, joints)

local function test_find_path(pos1, pos2)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", pos1.x, pos1.y, pos2.x, pos2.y))
    local ret = nav:find_path(pos1, pos2)
    for _, v in ipairs(ret) do
        print(v.x, v.y)
    end
    print("========================")
end

test_find_path({ x = 1, y = 1 }, { x = 10, y = 10 })
