local navigation = require "navigation"
local nav = navigation.new (20, 20, {
    {1, 0},
})

local function test_find_path(pos1, pos2)
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", pos1.x, pos1.y, pos2.x, pos2.y))
    local ret = nav:find_path(pos1, pos2)
    for _, v in ipairs(ret) do
        print(v[1], v[2])
    end
    print("========================")
end

test_find_path({x = 1, y = 1}, {x = 0, y = 0})
test_find_path({x = 0, y = 0}, {x = 1, y = 1})
test_find_path({x = 1, y = 1}, {x = 0, y = 0})
