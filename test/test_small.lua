-- 测试小地图
local test = require "test.test_api"
local nav = test.set_nav {
    w = 20,
    h = 20,
    obstacle = {}
}

for i = 1, 18 do
    nav:add_block(4, i)
end

nav:dump()
test.set_start(0.1, 10.6)
test.set_end(15.6, 15.2)
test.print_find_path()

test.set_start(0, 10)
test.set_end(15, 15)
test.print_find_path_by_grid()
test.print_find_path_by_grid(true)