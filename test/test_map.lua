local navigation = require "navigation"
local map = require "test.world_map"

local obstacle_list = {}
for _, v in pairs(map.obstacles) do
    local x = v % map.width
    local y = v // map.width
    table.insert(obstacle_list, {x, y})
end

local nav = navigation.new {
    w = map.width,
    h = map.height,
    obstacle = obstacle_list
}
nav:mark_connected()

local function test_find_path(x1, y1, x2, y2)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", x1, y1, x2, y2))
    local ret = nav:find_path(x1, y1, x2, y2)
    for _, v in ipairs(ret) do
        print(v[1], v[2])
    end
    print("========================")
end

test_find_path(15, 0, 1500, 0)
