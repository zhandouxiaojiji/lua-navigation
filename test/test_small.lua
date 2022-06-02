-- 测试小地图
local test = require "test.test_api"
local navigation = require "navigation"
local nav = navigation.new {
    w = 20,
    h = 20,
    obstacle = {}
}

for i = 1, 18 do
    nav:add_block(4, i)
end

nav:dump()
test.print_find_path(nav, 0.1, 10.2, 15.2, 15.9)
test.print_find_path_by_grid(0, 10, 15, 15)