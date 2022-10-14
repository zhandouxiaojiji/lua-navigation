local navigation = require "navigation.c"
local nav = navigation.new {
    w = 20,
    h = 20,
    obstacle = {
        -- {1, 0},
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

-- test_line_walkable(0, 0, 1, 3)
-- test_line_walkable(0, 0, 3.5, 3)

-- test_find_path(0, 0, 1, 3.3)
-- test_find_path_by_grid(0, 0, 1, 3)

test_find_path(1, 1, 0, 0)
test_find_path(0, 0, 1, 1)
test_find_path(1, 1, 0, 0)
