local test = require "test.test_api"

local nav = test.set_nav {
    w = 5000,
    h = 5000,
    obstacle = {
    }
}

test.set_start(0, 0)
test.set_end(2498, 2499)

for i = 1, 1000000 do
    local x = math.random(0, 4999)
    local y = math.random(0, 4999)
    if x ~= x1 and x ~= x2 and y ~= y1 and y ~= y2 then
        nav:add_block(x, y)
    end
end

print("find_path")
test.calc_time(function ()
    test.find_path()
end, 100)

print("find_path_by_grid")
test.calc_time(function ()
    test.find_path_by_grid()
end, 100)

print("find_path_by_grid without smooth")
test.calc_time(function ()
    test.find_path_by_grid(true)
end, 100)



