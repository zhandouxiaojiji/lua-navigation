local navigation_c = require "navigation.c"

local mfloor = math.floor
local sqrt = math.sqrt

---@class LuaNavigationPosition
---@field x number
---@field y number

---@class LuaNavigation
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
    ---@class LuaNavigationNode
    local node = {
        cell = cell,
        pos = pos,
        g = 0,
        h = 0,
        f = 0,
        prev = nil,
        connected = {} -- {node -> {path, length}}
    }
    return node
end

local function create_graph()
    ---@class LuaNavigationGraph
    local graph = {
        nodes = {},
        open_set = {},
        closed_set = {},
    }
    return graph
end

local function create_area(area_id)
    ---@class LuaNavigationArea
    local area = {
        area_id = area_id,
        paths = {},  -- {[from][to] -> path}
        joints = {}, -- {cell -> true}
    }
    return area
end

---@param pos1 LuaNavigationPosition
---@param pos2 LuaNavigationPosition
---@return number
local function calc_distance(pos1, pos2)
    return sqrt((pos1.x - pos2.x) ^ 2 + (pos1.y - pos2.y) ^ 2)
end

---@param path LuaNavigationPosition[]
---@return number
local function calc_path_length(path)
    local len = 0
    for i = 1, #path - 1 do
        local pos1 = path[i]
        local pos2 = path[i + 1]
        len = len + calc_distance(pos1, pos2)
    end
    return len
end

---@param path LuaNavigationPosition[]
---@return LuaNavigationPosition[]
local function reverse_path(path)
    local new = {}
    for i = #path, 1, -1 do
        new[#new + 1] = path[i]
    end
    return new
end

---@param self LuaNavigation
---@param node1 LuaNavigationNode
---@param node2 LuaNavigationNode
local function connect_nodes(self, node1, node2)
    local path = self:find_path(node1.pos, node2.pos)
    local length = calc_path_length(path)
    node1.connected[node2] = { path, length }
    node2.connected[node1] = { reverse_path(path), length }
end


---@param self LuaNavigation
---@param node1 LuaNavigationNode
---@param node2 LuaNavigationNode
local function disconnect_nodes(self, node1, node2)
    node1.connected[node2] = nil
    node2.connected[node1] = nil
end

---@param node1 LuaNavigationNode
---@param node2 LuaNavigationNode
local function connect_nodes_cross_area(node1, node2)
    local distance = calc_distance(node1.pos, node2.pos)
    node1.connected[node2] = { { node1.pos, node2.pos }, distance }
    node2.connected[node1] = { { node2.pos, node1.pos }, distance }
end

---@param self LuaNavigation
---@param cell number
---@return LuaNavigationNode
local function get_node(self, cell)
    return self.graph.nodes[cell]
end

---@param self LuaNavigation
---@param area LuaNavigationArea
---@param pos LuaNavigationPosition
local function area_add_joint(self, area, pos)
    local cell = pos2cell(self, pos)
    local nodes = self.graph.nodes
    local node = nodes[cell]
    if not node then
        node = create_node(cell, pos)
        nodes[cell] = node
    end
    area.joints[cell] = node
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

---@param self LuaNavigation
---@param area LuaNavigationArea
---@param pos LuaNavigationPosition
local function area_del_joint(self, area, pos)
    local cell = pos2cell(self, pos)
    local nodes = self.graph.nodes
    local node = nodes[cell]
    if node then
        for from in pairs(node.connected) do
            from.connected[node] = nil
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

function mt:is_obstacle(pos)
    return self.core:is_block(mfloor(pos.x), mfloor(pos.y))
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

local function find_walkable_area_around(self, center_pos, max_size)
    local cx = mfloor(center_pos.x)
    local cy = mfloor(center_pos.y)
    for i = 0, max_size do
        for j = 0, max_size do
            if not self.core:is_block(cx + i, cy + j) then
                return self:get_area_id_by_pos(center_pos)
            end
        end
    end
end

---@param center_pos LuaNavigationPosition
---@param camp? number
---@param max_size? number
---@param joints? LuaNavigationPosition[]
function mt:add_portal(center_pos, camp, max_size, joints)
    local cell = pos2cell(self, center_pos)
    ---@class LuaNavigationPortal
    local portal = {
        cell = cell, ---@type number
        camp = camp, ---@type number?
        joints = {} ---@type LuaNavigationPosition[]
    }
    self.portals[cell] = portal
    local cx = mfloor(center_pos.x)
    local cy = mfloor(center_pos.y)
    max_size = max_size or 10
    if joints then
        -- 从关节点向中心点反方向寻找空白格
        for _, pos in pairs(joints) do
            local direction_x = pos.x - center_pos.x
            local direction_y = pos.y - center_pos.y
            local step_x = direction_x ~= 0 and direction_x / math.abs(direction_x) or 0
            local step_y = direction_y ~= 0 and direction_y / math.abs(direction_y) or 0
            local current_x = pos.x
            local current_y = pos.y

            while math.abs(current_x - center_pos.x) <= max_size and math.abs(current_y - center_pos.y) <= max_size do
                if not self.core:is_block(mfloor(current_x), mfloor(current_y)) then
                    table.insert(portal.joints, { x = current_x + 0.5, y = current_y + 0.5 })
                    break
                end
                current_x = current_x + step_x
                current_y = current_y + step_y
            end
        end
    else
        for i = 1, max_size // 2 do
            if not self.core:is_block(cx - i, cy) and not self.core:is_block(cx + i, cy) then
                portal.joints = {
                    { x = cx - i + 0.5, y = cy + 0.5 },
                    { x = cx + i + 0.5, y = cy + 0.5 },
                }
                break
            end
            if not self.core:is_block(cx, cy - i) and not self.core:is_block(cx, cy + i) then
                portal.joints = {
                    { x = cx + 0.5, y = cy - i + 0.5 },
                    { x = cx + 0.5, y = cy + i + 0.5 },
                }
                break
            end
        end
    end
    local last_node
    for _, pos in pairs(portal.joints) do
        local area_id = self:get_area_id_by_pos(pos)
        local area = self:get_area(area_id)
        local node = area_add_joint(self, area, pos)
        if last_node then
            connect_nodes_cross_area(node, last_node)
        else
            last_node = node
        end
    end
end

function mt:del_portal(pos)
    local cell = pos2cell(self, pos)
    local portal = self.portals[cell]
    if portal then
        for _, joint in pairs(portal.joints) do
            local area_id = self:get_area_id_by_pos(joint)
            local area = self:get_area(area_id)
            area_del_joint(self, area, joint)
        end
        self.portals[cell] = nil
    else
        print("not found portal", cell)
    end
end

local function connect_to_area(area, node)
    for _, joint in pairs(area.joints) do
        local distance = calc_distance(node.pos, joint.pos)
        node.connected[joint] = { { node.pos, joint.pos }, distance }
        joint.connected[node] = { { joint.pos, node.pos }, distance }
    end
end

local function disconnect_to_area(area, node)
    for _, joint in pairs(area.joints) do
        node.connected[joint] = nil
        joint.connected[node] = nil
    end
end

local function merge_path(path1, path2)
    for _, v in ipairs(path2) do
        path1[#path1 + 1] = v
    end
end

local function find_path_cross_area(self, src_area_id, src_pos, dst_area_id, dst_pos)
    print("find_path_cross_area")
    local graph = self.graph
    graph.open_set = {}
    graph.closed_set = {}

    local src_cell = pos2cell(self, src_pos)
    local dst_cell = pos2cell(self, dst_pos)
    local src_node = create_node(src_cell, src_pos)
    local dst_node = create_node(dst_cell, dst_pos)
    local src_area = self:get_area(src_area_id)
    local dst_area = self:get_area(dst_area_id)

    connect_to_area(src_area, src_node)
    connect_to_area(dst_area, dst_node)

    local path = {}

    local ok, errmsg = xpcall(function()
        local function add_to_open_set(node, prev)
            if graph.open_set[node] or graph.closed_set[node] then
                return
            end
            graph.open_set[node] = true
            node.prev = prev
            if prev then
                node.g = prev.g + calc_distance(node.pos, prev.pos)
            else
                node.g = 0
            end
            node.h = calc_distance(node.pos, dst_pos)
            node.f = node.g + node.h
        end
        add_to_open_set(src_node)
        while next(graph.open_set) do
            local cur_node
            for node in pairs(graph.open_set) do
                if not cur_node then
                    cur_node = node
                else
                    if node.f < cur_node.f then
                        cur_node = node
                    end
                end
            end
            graph.open_set[cur_node] = nil
            graph.closed_set[cur_node] = true
            for node in pairs(cur_node.connected) do
                if not graph.closed_set[node] and not graph.open_set[node] then
                    add_to_open_set(node, cur_node)
                end
            end
        end

        if not dst_node.prev then
            return {}
        end
        local node_path = {}
        local node = dst_node
        while true do
            node_path[#node_path + 1] = node
            if node == src_node then
                break
            end
            node = node.prev
        end

        node_path = reverse_path(node_path)
        local first = node_path[1]
        local second = node_path[2]
        first.connected[second][1] = self:find_path(first.pos, second.pos)
        local last = node_path[#node_path]
        local last_second = node_path[#node_path - 1]
        last_second.connected[last][1] = self:find_path(last_second.pos, last.pos)

        for i = 1, #node_path - 1 do
            local cur_node = node_path[i]
            local next_node = node_path[i + 1]
            local part = cur_node.connected[next_node][1]
            part[#part] = nil
            merge_path(path, part)
        end
        path[#path + 1] = last.pos
    end, debug.traceback)
    if not ok then
        print(errmsg)
    end

    disconnect_to_area(src_area, src_node)
    disconnect_to_area(dst_area, dst_node)

    return path
end

function mt:find_path(from_pos, to_pos, check_portal_func, ignore_list)
    ignore_list = ignore_list or {}
    if self.core:is_block(mfloor(from_pos.x), mfloor(from_pos.y)) then
        ignore_list[#ignore_list + 1] = from_pos -- 自动忽略起点
    end
    for _, pos in pairs(ignore_list) do
        self.core:clear_block(mfloor(pos.x), mfloor(pos.y))
    end
    local path
    local from_area_id = self:get_area_id_by_pos(from_pos)
    local to_area_id = self:get_area_id_by_pos(to_pos)
    local ok, errmsg = xpcall(function()
        if from_area_id == to_area_id then
            local cpath = self.core:find_path(from_pos.x, from_pos.y, to_pos.x, to_pos.y) or {}
            path = {}
            for _, pos in ipairs(cpath) do
                path[#path + 1] = {
                    x = pos[1],
                    y = pos[2]
                }
            end
        else
            path = find_path_cross_area(self, from_area_id, from_pos, to_area_id, to_pos)
        end
    end, debug.traceback)
    if not ok then
        print(errmsg)
    end

    for _, pos in pairs(ignore_list) do
        self.core:add_block(mfloor(pos.x), mfloor(pos.y))
    end
    if #path < 2 then
        print(string.format("cannot find path (%s, %s) =>(%s, %s)", from_pos.x, from_pos.y, to_pos.x, to_pos.y))
    end
    return path
end

local M = {}
function M.new(w, h, obstacles)
    local obj = setmetatable({}, mt)
    obj:init(w, h, obstacles)
    return obj
end

return M
