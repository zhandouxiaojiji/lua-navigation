local navigation = require "navigation"
local nav = navigation.new {
    w = 20,
    h = 20,
    obstacle = {
    }
}

local ret = nav:find_path(0, 0, 1, 7)
for k, v in ipairs(ret) do
    print(v[1], v[2])
end