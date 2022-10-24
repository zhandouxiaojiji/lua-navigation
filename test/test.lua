local navigation = require "navigation"
local w = 20
local h = 20
local nav = navigation.new (w, h, {
    -- {1, 0},
})

for x = 0, w - 1 do
    nav:set_obstacle {x = x, y = 5}
    nav:set_obstacle {x = x, y = 15}
end
for y = 0, h - 1 do
    nav:set_obstacle {x = 5, y = y}
    nav:set_obstacle {x = 15, y = y}
end

nav:update_areas()
nav.core:dump()
nav.core:dump_connected()

nav:add_portal({x = 5, y = 3})
nav:add_portal({x = 15, y = 10})
nav:add_portal({x = 10, y = 5})
nav:add_portal({x = 19, y = 15})


local function test_find_path(pos1, pos2)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", pos1.x, pos1.y, pos2.x, pos2.y))
    local ret = nav:find_path(pos1, pos2)
    for _, v in ipairs(ret) do
        print(v.x, v.y)
    end
    print("========================")
end

-- test_find_path({x = 1, y = 1}, {x = 0, y = 0})
-- test_find_path({x = 0, y = 0}, {x = 1, y = 1})
-- test_find_path({x = 1, y = 1}, {x = 0, y = 0})
test_find_path({x = 1, y = 1}, {x = 6, y = 1})
test_find_path({x = 1, y = 1}, {x = 19, y = 19})
