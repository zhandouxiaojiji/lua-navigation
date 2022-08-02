
local world_map = require "test.world_map"
-- 测试小地图
local test = require "test.test_api"
local nav = test.set_nav {
    w = world_map.width,
    h = world_map.height,
    obstacle = world_map.obstacles,
}

for x = 22, 24 do
    for y = 22, 24 do
        nav:add_block(x, y)
    end
end


-- nav:dump()
test.set_start(24.60000038147, 29.39999961853)
test.set_end(22.799999237061, 16.89999961853)
test.print_find_path()
