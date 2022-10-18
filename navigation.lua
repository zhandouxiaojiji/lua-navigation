local navigation_c = require "navigation.c"

local mfloor = math.floor
local sqrt = math.sqrt

local mt = {}
mt.__index = mt

local function pos2cell(self, pos)
    local x = mfloor(pos.x)
    local y = mfloor(pos.y)
    return y * self.w + x
end

local function cell2pos(self, cell)
    return {
        x = cell % self.w + 0.5,
        y = cell // self.w
    }
end

local function create_node(cell)
    return {
        cell = cell,
        connected = {} -- {node -> length}
    }
end

local function create_graph()
    return {
        nodes = {},
    }
end

local function create_area(area_id)
    return {
        area_id = area_id,
        paths = {}, -- {[from][to] -> path}
        joints = {}, -- {cell -> true}
    }
end

local function calc_path_length(path)
    local len = 0
    for i = 1, #path - 1 do
        local pos1 = path[i]
        local pos2 = path[i+1]
        len = len + sqrt((pos1.x - pos2.x) ^ 2 + (pos1.y - pos2.y) ^ 2)
    end
    return len
end

local function area_add_joint(self, area, pos)
    local cell = pos2cell(self, pos)
    area.joints[cell] = true
    local nodes = self.graph.nodes
    for v in pairs(area.joints) do
        if not nodes[v] then
            nodes[v] = create_node(v)
        end
    end
    for from in pairs(area.joints) do
        for to in pairs(area.joints) do
            if not area.path[from][to] then
                local path = self:find_path(cell2pos(from), cell2pos(to))
                area.path[from][to] = path
                local from_node = nodes[from]
                local to_node = nodes[to]
                local length = calc_path_length(path)
                from_node.connected[to_node] = length
                to_node.connected[from_node] = length
            end
        end
    end

end

function mt:init(w, h, obstacles)
    self.w = w
    self.h = h
    self.core = navigation_c.new {
        w = w,
        h = h,
        obstacle = obstacles,
    }
    self.portals = {}
    self.areas = {}

    self.graph = create_graph()
end

function mt:set_obstacle(pos)
    self.core:add_block(mfloor(pos.x), mfloor(pos.y))
end

function mt:unset_obstacle(pos)
    self.core:clear_block(mfloor(pos.x), mfloor(pos.y))
end

function mt:get_area_id_by_pos(pos)
    return self.core:get_connected_id(mfloor(pos.x), mfloor(pos.y))
end

function mt:get_area(area_id)
    local area = self.areas[area_id]
    if not area then
        area = create_area(area_id)
        self.areas[area_id] = area
    end
    return area
end

function mt:add_portal(center_pos, camp, max_size)
    local cell = pos2cell(self, center_pos)
    local portal = {
        cell = cell,
        camp = camp,
        joints = {}
    }
    self.portals[cell] = portal
    local cx = mfloor(center_pos.x)
    local cy = mfloor(center_pos.y)
    max_size = max_size or 10
    for i = 1, max_size // 2 do
        if not self.core:is_block(cx - i, cy) and not self.core:is_block(cx + i, cy) then
            portal.joints = {
                {x = cx - i + 0.5, y = cy + 0.5},
                {x = cx + i + 0.5, y = cy + 0.5},
            }
            break
        end
        if not self.core:is_block(cx, cy - i) and not self.core:is_block(cx, cy + i) then
            portal.joints = {
                {x = cx + 0.5, y = cy - i + 0.5},
                {x = cx + 0.5, y = cy + i + 0.5},
            }
            break
        end
    end
    for _, pos in pairs(portal.joints) do
        local area_id = self:get_area_id_by_pos(pos)
        local area = self:get_area(area_id)
        area_add_joint(self, area, pos)
    end
end

function mt:del_portal(pos)
    local cell = pos2cell(self, pos)
    print("todo del_portal", cell)
    -- TODO
end

function mt:find_path(from, to, check_portal_func, ignore_list)
    ignore_list = ignore_list or {}
    if self.core:is_block(mfloor(from.x), mfloor(from.y)) then
        ignore_list[#ignore_list+1] = from -- 自动忽略起点
    end
    for _, pos in pairs(ignore_list) do
        self.core:clear_block(mfloor(pos.x), mfloor(pos.y))
    end
    local path
    local ok, errmsg = xpcall(function()
        path = self.core:find_path(from.x, from.y, to.x, to.y) or {}
    end, debug.traceback)
    if not ok then
        print(errmsg)
    end
    for _, pos in pairs(ignore_list) do
        self.core:add_block(mfloor(pos.x), mfloor(pos.y))
    end
    if #path < 2 then
        print(string.format("cannot find path (%s, %s) =>(%s, %s)", from.x, from.y, to.x, to.y))
    end
    local new = {}
    for _, pos in ipairs(path) do
        new[#new+1] = {
            x = pos[1],
            y = pos[2]
        }
    end
    return new
end

local M = {}
function M.new(w, h, obstacles)
    local obj = setmetatable({}, mt)
    obj:init(w, h, obstacles)
    return obj
end

return M