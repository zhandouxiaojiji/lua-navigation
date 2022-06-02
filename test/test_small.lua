-- 测试小地图
local navigation = require "navigation"
local nav = navigation.new {
    w = 20,
    h = 20,
    obstacle = {}
}

for i = 1, 18 do
    nav:add_block(4, i)
end

local function test_find_path_by_grid(x1, y1, x2, y2)
    print("========================")
    print(string.format("find path by grid (%s, %s) => (%s, %s)", x1, y1, x2, y2))
    local ret = nav:find_path_by_grid(x1, y1, x2, y2)
    for _, v in ipairs(ret) do
        print(v[1], v[2])
    end
    print("========================")
end

local function test_find_path(x1, y1, x2, y2)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", x1, y1, x2, y2))
    local ret = nav:find_path(x1, y1, x2, y2)
    for _, v in ipairs(ret) do
        print(v[1], v[2])
    end
    print("========================")
end

nav:dump()
test_find_path_by_grid(0, 10, 15, 15)
test_find_path(0.1, 10.2, 15.2, 15.9)