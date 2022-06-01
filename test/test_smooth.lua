local navigation = require "navigation"
local nav = navigation.new {
    w = 5,
    h = 5,
    obstacle = {
        {1, 2},
    }
}

local function test_line_walkable(x1, y1, x2, y2)
    local ret = nav:check_line_walkable(x1, y1, x2, y2)
    print(string.format("check_line_walkable (%s, %s) => (%s, %s), %s", x1, y1, x2, y2, ret))
    return ret
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

-- test_find_path(1.5, 3.5, 2.5, 2.5)
test_find_path(1.1, 3.1, 2.1, 2.1)
test_find_path(2.1, 2.1, 1.1, 3.1)
