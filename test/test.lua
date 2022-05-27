local navigation = require "navigation"
local nav = navigation.new {
    w = 20,
    h = 20,
    obstacle = {
    }
}

nav:set_start(0, 0)
nav:set_end(1, 7)
local ret = nav:find_path()
for k, v in ipairs(ret) do
    print(v[1], v[2])
end