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

local function create_node(cell, pos)
    return {
        cell = cell,
        pos = pos,
        connected = {} -- {node -> {path, length}}
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

local function reverse_path(path)
    local new = {}
    for i = #path, 1, -1 do
        new[#new+1] = path[i]
    end
    return new
end

local function connect_nodes(self, node1, node2)
    local path = self:find_path(node1.pos, node2.pos)
    local length = calc_path_length(path)
    node1.connected[node2] = {path, length}
    node2.connected[node1] = {reverse_path(path), length}
end

local function get_node(self, cell)
    return self.graph.nodes[cell]
end

local function area_add_joint(self, area, pos)
    local cell = pos2cell(self, pos)
    area.joints[cell] = true
    local nodes = self.graph.nodes
    local node = nodes[cell]
    if not node then
        node = create_node(cell)
        nodes[cell] = node
    end
    for from in pairs(area.joints) do
        for to in pairs(area.joints) do
            if from ~= to then
                local node1 = get_node(self, from)
                local node2 = get_node(self, to)
                if not node1.connected[node2] then
                    connect_nodes(self, node1, node2)
                end
            end
        end
    end
    return node
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
    self:update_areas()
end

function mt:update_areas()
    self.core:mark_connected()
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
    local last_node
    for _, pos in pairs(portal.joints) do
        local area_id = self:get_area_id_by_pos(pos)
        local area = self:get_area(area_id)
        local node = area_add_joint(self, area, pos)
        if last_node then
            connect_nodes(self, node, last_node)
        else
            last_node = node
        end
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