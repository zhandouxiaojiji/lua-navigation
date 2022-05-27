local navigation = require "navigation"
local nav = navigation.new {
    w = 20,
    h = 20,
    obstacle = {
        {1, 0},
    }
}

print("========================")
local ret = nav:find_path(0, 0, 1, 7)
for k, v in ipairs(ret) do
    print(v[1], v[2])
end
print("========================")

print("check_line_walkable", nav:check_line_walkable(0, 0, 1, 7));
print("check_line_walkable", nav:check_line_walkable(0, 0, 3.5, 1));
