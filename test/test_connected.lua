local test = require "test.test_api"
local nav = test.set_nav {
    w = 20,
    h = 20,
    obstacle = {}
}

for i = 1, 18 do
    nav:add_block(4, i)
    nav:add_block(10, i)
    nav:add_block(i, 4)
    nav:add_block(i, 10)
end

nav:dump()
test.set_start(0.1, 0.6)
test.set_end(9, 9)
test.print_find_path()

print("test without mark connected")
test.calc_time(function ()
    test.find_path()
end, 100000)

print("test with mark connected")
nav:mark_connected()
nav:dump_connected()
test.calc_time(function ()
    test.find_path()
end, 100000)