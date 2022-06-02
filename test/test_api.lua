local navigation = require "navigation"
local M = {}

local nav, x1, y1, x2, y2
function M.set_nav(...)
    nav = navigation.new(...)
    return nav
end

function M.set_start(x, y)
    x1 = x
    y1 = y
end

function M.set_end(x, y)
    x2 = x
    y2 = y
end

function M.find_path()
    nav:find_path(x1, y1, x2, y2)
end

function M.find_path_by_grid(without_smooth)
    nav:find_path(x1, y1, x2, y2, without_smooth)
end


function M.print_find_path()
    print("========================")
    print(string.format("find path (%s, %s) => (%s, %s)", x1, y1, x2, y2))
    local ret = nav:find_path(x1, y1, x2, y2)
    for _, v in ipairs(ret or {}) do
        print(v[1], v[2])
    end
    print("========================")
end

function M.print_find_path_by_grid(without_smooth)
    print("========================")
    print(string.format("find path by grid %s (%s, %s) => (%s, %s)",
        without_smooth and "without_smooth" or nil, x1, y1, x2, y2))
    local ret = nav:find_path_by_grid(x1, y1, x2, y2, without_smooth)
    for _, v in ipairs(ret or {}) do
        print(v[1], v[2])
    end
    print("========================")
end

function M.calc_time(func, count)
    count = count or 1
    local t = os.clock()
    for i = 1, count do
        func()
    end
    local sum = os.clock() - t
    print(string.format("run time, count:%d, sum time:%.2f, average:%.2f", count, sum, sum/count))
end


return M