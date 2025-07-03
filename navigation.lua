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
        nodes = {},     ---@type {[number]: LuaNavigationNode}
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

---@generic T
---@param path T[]
---@return T[]
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

function mt:set_connected_id(pos, id)
    self.core:set_connected_id(mfloor(pos.x), mfloor(pos.y), id)
end

function mt:get_max_connected_id()
    return self.core:get_max_connected_id()
end

function mt:quick_remark_area(change_pos)
    local x = mfloor(change_pos.x)
    local y = mfloor(change_pos.y)
    
    -- 检查起点是否为阻挡点
    if not self.core:is_block(x, y) then
        error(string.format("Position (%d,%d) is not a block", x, y))
    end
    
    -- 1. 从起点开始扩展找所有连通的阻挡点，构建包围盒
    local visited = {}
    local queue = {}
    local min_x, max_x = x, x
    local min_y, max_y = y, y
    
    -- 初始化队列
    local function pos_key(px, py)
        return px + py * self.w
    end
    
    local function add_to_queue(px, py)
        local key = pos_key(px, py)
        if not visited[key] and 
           px >= 0 and px < self.w and 
           py >= 0 and py < self.h and
           self.core:is_block(px, py) then
            visited[key] = true
            queue[#queue + 1] = {px, py}
            return true
        end
        return false
    end
    
    add_to_queue(x, y)
    
    -- BFS扩展找所有相邻的阻挡点
    local head = 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        local cx, cy = cur[1], cur[2]
        
        -- 更新包围盒
        if cx < min_x then min_x = cx end
        if cx > max_x then max_x = cx end
        if cy < min_y then min_y = cy end
        if cy > max_y then max_y = cy end
        
        -- 检查四个方向的相邻阻挡点
        add_to_queue(cx - 1, cy)  -- 左
        add_to_queue(cx + 1, cy)  -- 右
        add_to_queue(cx, cy - 1)  -- 上
        add_to_queue(cx, cy + 1)  -- 下
    end
    
    -- 2. 扩展包围盒边界，确保能找到完整的空洞
    min_x = math.max(0, min_x - 1)
    max_x = math.min(self.w - 1, max_x + 1)
    min_y = math.max(0, min_y - 1)
    max_y = math.min(self.h - 1, max_y + 1)
    
    -- 3. 在包围盒内找空洞并重新标记分区
    local hole_visited = {}
    local new_connected_id = self.core:get_max_connected_id() + 1
    
    local function hole_pos_key(px, py)
        return px + py * self.w
    end
    
    -- 遍历包围盒内的所有点
    for yy = min_y, max_y do
        for xx = min_x, max_x do
            local key = hole_pos_key(xx, yy)
            
            -- 如果这个点不是阻挡，且没有被访问过，则可能是空洞的一部分
            if not self.core:is_block(xx, yy) and not hole_visited[key] then
                -- 用BFS找这个连通区域
                local hole_queue = {}
                local hole_points = {}
                local is_new_hole = true
                
                hole_queue[#hole_queue + 1] = {xx, yy}
                hole_visited[key] = true
                
                local hole_head = 1
                while hole_head <= #hole_queue do
                    local cur = hole_queue[hole_head]
                    hole_head = hole_head + 1
                    local cx, cy = cur[1], cur[2]
                    
                    hole_points[#hole_points + 1] = {cx, cy}
                    
                    -- 检查空洞边缘是否超出原始包围盒
                    -- 如果触及到原始包围盒的边界，说明这不是一个封闭的新空洞
                    if (cx == min_x and min_x > 0) or 
                       (cx == max_x and max_x < self.w - 1) or
                       (cy == min_y and min_y > 0) or 
                       (cy == max_y and max_y < self.h - 1) then
                        is_new_hole = false
                    end
                    
                    -- 扩展到相邻的非阻挡点
                    local directions = {
                        {cx - 1, cy},  -- 左
                        {cx + 1, cy},  -- 右
                        {cx, cy - 1},  -- 上
                        {cx, cy + 1}   -- 下
                    }
                    
                    for _, dir in ipairs(directions) do
                        local nx, ny = dir[1], dir[2]
                        local nkey = hole_pos_key(nx, ny)
                        
                        if nx >= min_x and nx <= max_x and 
                           ny >= min_y and ny <= max_y and
                           not self.core:is_block(nx, ny) and 
                           not hole_visited[nkey] then
                            hole_visited[nkey] = true
                            hole_queue[#hole_queue + 1] = {nx, ny}
                        end
                    end
                end
                
                -- 如果是新空洞（完全被包围盒内的阻挡点包围），给它分配新的连通ID
                if is_new_hole and #hole_points > 0 then
                    for _, point in ipairs(hole_points) do
                        self.core:set_connected_id(point[1], point[2], new_connected_id)
                    end
                    new_connected_id = new_connected_id + 1
                end
            end
        end
    end
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
    for i = 1, #path2-1 do
        path1[#path1 + 1] = { x = path2[i].x, y = path2[i].y }
    end
end

local function table_2_string(tbl)
    if not tbl then
        return nil
    end

    local set = {}
    local function traverse_tbl(tmp_tbl)
        local t = {}
        for k, v in pairs(tmp_tbl) do
            local s
            if type(v) == "table" then
                if not set[v] then
                    set[v] = true
                    s = string.format("%s:%s", k, traverse_tbl(v))
                end
            else
                s = string.format("%s:%s", k, v)
            end
            t[#t+1] = s
        end
        return string.format("[%s]", table.concat(t, ", "))
    end
    local result = traverse_tbl(tbl)
    return result
end

---@param self LuaNavigation
local function find_path_cross_area(self, src_area_id, src_pos, dst_area_id, dst_pos)
    local graph = self.graph
    local open_set = {}
    local closed_set = {}

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
            if open_set[node] or closed_set[node] then
                return
            end
            open_set[node] = true
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
        while next(open_set) do
            local cur_node
            for node in pairs(open_set) do
                if not cur_node then
                    cur_node = node
                else
                    if node.f < cur_node.f then
                        cur_node = node
                    end
                end
            end
            open_set[cur_node] = nil
            closed_set[cur_node] = true
            for node in pairs(cur_node.connected) do
                if not closed_set[node] and not open_set[node] then
                    add_to_open_set(node, cur_node)
                end
            end
        end

        if not dst_node.prev then
            return {}
        end
        local node_path = {}    ---@type LuaNavigationNode[]
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

local DIR_OFFSET = {    ---@type LuaNavigationPosition[] 顺时针方向
    {x = -1, y = -1},
    {x = 0, y = -1},
    {x = 1, y = -1},
    {x = 1, y = 0},
    {x = 1, y = 1},
    {x = 0, y = 1},
    {x = -1, y = 1},
    {x = -1, y = 0},
}

---@param self LuaNavigation
---@param pos LuaNavigationPosition
---@param max_size number
local function find_nearest_joint(self, pos, max_size)
    local tmp_pos = {x = pos.x, y = pos.y}
    local nodes = self.graph.nodes
    for i = 1, max_size do
        for _, dir in pairs(DIR_OFFSET) do
            tmp_pos.x = pos.x + dir.x * i
            tmp_pos.y = pos.y + dir.y * i
            local cell = pos2cell(self, tmp_pos)
            local node = nodes[cell]
            if node then
                return node.pos
            end
        end
    end
end

local function find_path_start_in_portal(self, from_area_id, from_pos, to_area_id, to_pos)
    local joint_pos = find_nearest_joint(self, from_pos, 5)
    if not joint_pos then
        return {}
    end
    local path = find_path_cross_area(self, self:get_area_id_by_pos(joint_pos), joint_pos, to_area_id, to_pos)
    if #path < 2 then
        return path
    end
    local first_point = path[1]
    first_point.x = from_pos.x
    first_point.y = from_pos.y
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
        elseif from_area_id == 0 then
            path = find_path_start_in_portal(self, from_area_id, from_pos, to_area_id, to_pos)
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
