local navigation_c = require "navigation.c"

local mfloor = math.floor
local sqrt = math.sqrt

---@class LuaNavigationPosition
---@field x number
---@field y number

---@class LuaNavigationNode
---@field cell number
---@field pos LuaNavigationPosition
---@field g number
---@field h number
---@field f number
---@field prev LuaNavigationNode
---@field connected table<LuaNavigationNode, {LuaNavigationPosition[], number}>
---@field disabled boolean 是否不可用

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
        connected = {}, -- {node -> {path, length}}
        disabled = false
    }
    return node
end

local function create_graph()
    ---@class LuaNavigationGraph
    local graph = {
        nodes = {}, ---@type {[number]: LuaNavigationNode}
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
                if not node1.connected[node2] and node2 then
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
    -- 清理节点
    self.graph.nodes[cell] = nil
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
    local cell = pos2cell(self, pos)
    -- 检查是否有连接点
    for _, area in pairs(self.areas) do
        local node = area.joints[cell]
        if node then
            node.disabled = true
        end
    end
    self.core:add_block(mfloor(pos.x), mfloor(pos.y))
end

function mt:unset_obstacle(pos)
    local cell = pos2cell(self, pos)
    -- 检查是否有连接点
    for _, area in pairs(self.areas) do
        local node = area.joints[cell]
        if node then
            node.disabled = false
        end
    end
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

    -- 记录所有受影响的传送点
    local affected_portals = {} -- {[portal_cell] = portal}

    -- 检查格子是否是传送点的连接点，如果是则记录其传送点
    local function check_portal_joint(px, py)
        local pos = {x = px + 0.5, y = py + 0.5}
        for portal_cell, portal in pairs(self.portals) do
            for _, joint in pairs(portal.joints) do
                if mfloor(joint.x) == px and mfloor(joint.y) == py then
                    affected_portals[portal_cell] = portal
                    break
                end
            end
        end
    end

    -- 设置区域id并检查变化
    local function set_area_id(px, py, new_id)
        local old_id = self.core:get_connected_id(px, py)
        if old_id ~= new_id then
            check_portal_joint(px, py)
        end
        self.core:set_connected_id(px, py, new_id)
    end

    local is_block = self.core:is_block(x, y)

    if is_block then
        -- 处理添加阻挡点的情况：找新产生的空洞
        self:_handle_add_block(x, y, set_area_id)
    else
        -- 处理移除阻挡点的情况：合并原来分离的区域
        self:_handle_remove_block(x, y, set_area_id)
    end

    -- 删除受影响的传送点
    local portals_to_readd = {}
    for portal_cell, portal in pairs(affected_portals) do
        portals_to_readd[#portals_to_readd + 1] = {
            pos = cell2pos(self, portal_cell),
            camp = portal.camp,
            radius = 10, -- 默认半径
            joints = portal.joints
        }
        self:del_portal(cell2pos(self, portal_cell))
    end

    -- 重新添加传送点
    for _, portal_info in ipairs(portals_to_readd) do
        self:add_portal(portal_info.pos, portal_info.camp)
    end
end

-- 修改_handle_add_block函数，添加set_area_id参数
function mt:_handle_add_block(x, y, set_area_id)
    -- 1. 先临时移除当前点的阻挡，获取原始连通状态
    self.core:clear_block(x, y)

    local directions = {
        { -1, 0 }, -- 左
        { 1, 0 },  -- 右
        { 0, -1 }, -- 上
        { 0, 1 }   -- 下
    }

    local neighbor_points = {}

    -- 收集周围不同的连通区域ID和对应的点（在移除阻挡点的状态下）
    for _, dir in ipairs(directions) do
        local nx, ny = x + dir[1], y + dir[2]
        if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h and
            not self.core:is_block(nx, ny) then
            local area_id = self.core:get_connected_id(nx, ny)
            if area_id > 0 then
                neighbor_points[#neighbor_points + 1] = { nx, ny, area_id }
            end
        end
    end

    -- 2. 重新添加阻挡点
    self.core:add_block(x, y)

    -- 3. 如果没有邻近点，直接返回
    if #neighbor_points == 0 then
        return
    end

    local function pos_key(px, py)
        return px + py * self.w
    end

    -- 4. 按area_id分组
    local area_groups = {}
    for _, point in ipairs(neighbor_points) do
        local area_id = point[3]
        if not area_groups[area_id] then
            area_groups[area_id] = {}
        end
        area_groups[area_id][#area_groups[area_id] + 1] = { point[1], point[2] }
    end

    local processed = {}
    local new_connected_id = self.core:get_max_connected_id() + 1

    -- 5. 对于每个有多个邻近点的area_id，检查是否被分割
    for area_id, points in pairs(area_groups) do
        if #points > 1 then
            -- 从第一个点开始BFS，看能连通到多少个同area_id的邻近点
            local first_point = points[1]
            local visited = {}
            local queue = {}
            local reachable_neighbors = {}

            queue[#queue + 1] = first_point
            visited[pos_key(first_point[1], first_point[2])] = true

            local head = 1
            while head <= #queue do
                local cur = queue[head]
                head = head + 1
                local cx, cy = cur[1], cur[2]

                -- 检查这个点是否是邻近点之一
                for _, neighbor in ipairs(points) do
                    if neighbor[1] == cx and neighbor[2] == cy then
                        reachable_neighbors[#reachable_neighbors + 1] = neighbor
                        break
                    end
                end

                -- 检查四个方向的相邻点
                for _, dir in ipairs(directions) do
                    local nx, ny = cx + dir[1], cy + dir[2]
                    local key = pos_key(nx, ny)

                    if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h and
                        not visited[key] and not self.core:is_block(nx, ny) then
                        local point_area_id = self.core:get_connected_id(nx, ny)
                        if point_area_id == area_id then
                            visited[key] = true
                            queue[#queue + 1] = { nx, ny }
                        end
                    end
                end
            end

            -- 6. 如果无法连通到所有邻近点，说明区域被分割了
            if #reachable_neighbors < #points then
                -- 标记第一个连通组件为已处理
                for _, point in ipairs(reachable_neighbors) do
                    processed[pos_key(point[1], point[2])] = true
                end

                -- 为其他不连通的邻近点分配新的区域ID
                for _, start_point in ipairs(points) do
                    local key = pos_key(start_point[1], start_point[2])
                    if not processed[key] then
                        -- 从这个点开始BFS，找出它的完整连通区域
                        local new_visited = {}
                        local new_queue = {}

                        new_queue[#new_queue + 1] = start_point
                        new_visited[key] = true

                        local new_head = 1
                        while new_head <= #new_queue do
                            local cur = new_queue[new_head]
                            new_head = new_head + 1
                            local cx, cy = cur[1], cur[2]

                            -- 设置新的区域ID
                            if set_area_id then
                                set_area_id(cx, cy, new_connected_id)
                            else
                                self.core:set_connected_id(cx, cy, new_connected_id)
                            end

                            -- 检查四个方向的相邻点
                            for _, dir in ipairs(directions) do
                                local nx, ny = cx + dir[1], cy + dir[2]
                                local nkey = pos_key(nx, ny)

                                if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h and
                                    not new_visited[nkey] and not self.core:is_block(nx, ny) then
                                    local point_area_id = self.core:get_connected_id(nx, ny)
                                    if point_area_id == area_id then
                                        new_visited[nkey] = true
                                        new_queue[#new_queue + 1] = { nx, ny }
                                    end
                                end
                            end
                        end

                        processed[key] = true
                        new_connected_id = new_connected_id + 1
                    end
                end
            else
                -- 所有邻近点都还能连通，标记为已处理
                for _, point in ipairs(points) do
                    processed[pos_key(point[1], point[2])] = true
                end
            end
        end
    end
end

-- 修改_handle_remove_block函数，添加set_area_id参数
function mt:_handle_remove_block(x, y, set_area_id)
    -- 1. 检查当前点周围的连通区域
    local directions = {
        { -1, 0 }, -- 左
        { 1, 0 },  -- 右
        { 0, -1 }, -- 上
        { 0, 1 }   -- 下
    }

    local neighbor_areas = {}
    local area_count = {}

    -- 收集周围不同的连通区域ID
    for _, dir in ipairs(directions) do
        local nx, ny = x + dir[1], y + dir[2]
        if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h and
            not self.core:is_block(nx, ny) then
            local area_id = self.core:get_connected_id(nx, ny)
            if area_id > 0 then
                if not neighbor_areas[area_id] then
                    neighbor_areas[area_id] = {}
                    area_count[area_id] = 0
                end
                neighbor_areas[area_id][#neighbor_areas[area_id] + 1] = { nx, ny }
                area_count[area_id] = area_count[area_id] + 1
            end
        end
    end

    -- 2. 如果周围有多个不同的连通区域，需要合并它们
    local area_ids = {}
    for area_id in pairs(neighbor_areas) do
        area_ids[#area_ids + 1] = area_id
    end

    if #area_ids > 1 then
        -- 选择最小的area_id作为目标ID
        table.sort(area_ids)
        local target_area_id = area_ids[1]

        -- 3. 从当前点开始，找出所有能连通到的区域
        local visited = {}
        local queue = {}
        local merged_points = {}

        local function pos_key(px, py)
            return px + py * self.w
        end

        -- 将当前点加入队列作为起点
        queue[#queue + 1] = { x, y }
        visited[pos_key(x, y)] = true
        merged_points[#merged_points + 1] = { x, y }

        -- BFS遍历所有能连通的点
        local head = 1
        while head <= #queue do
            local cur = queue[head]
            head = head + 1
            local cx, cy = cur[1], cur[2]

            -- 检查四个方向的相邻点
            for _, dir in ipairs(directions) do
                local nx, ny = cx + dir[1], cy + dir[2]
                local key = pos_key(nx, ny)

                if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h and
                    not visited[key] and not self.core:is_block(nx, ny) then
                    local area_id = self.core:get_connected_id(nx, ny)

                    -- 如果是需要合并的区域之一
                    if neighbor_areas[area_id] then
                        visited[key] = true
                        queue[#queue + 1] = { nx, ny }
                        merged_points[#merged_points + 1] = { nx, ny }
                    end
                end
            end
        end

        -- 4. 将所有合并的点设置为目标区域ID
        for _, point in ipairs(merged_points) do
            if set_area_id then
                set_area_id(point[1], point[2], target_area_id)
            else
                self.core:set_connected_id(point[1], point[2], target_area_id)
            end
        end

        -- 5. 使用BFS找出与合并点连通的所有区域，统一设置ID
        local final_visited = {}
        local final_queue = {}

        -- 将所有合并点作为种子加入队列
        for _, point in ipairs(merged_points) do
            local key = pos_key(point[1], point[2])
            if not final_visited[key] then
                final_visited[key] = true
                final_queue[#final_queue + 1] = point
            end
        end

        local final_head = 1
        while final_head <= #final_queue do
            local cur = final_queue[final_head]
            final_head = final_head + 1
            local cx, cy = cur[1], cur[2]

            -- 检查四个方向的相邻点
            for _, dir in ipairs(directions) do
                local nx, ny = cx + dir[1], cy + dir[2]
                local key = pos_key(nx, ny)

                if nx >= 0 and nx < self.w and ny >= 0 and ny < self.h and
                    not final_visited[key] and not self.core:is_block(nx, ny) then
                    final_visited[key] = true
                    final_queue[#final_queue + 1] = { nx, ny }
                    if set_area_id then
                        set_area_id(nx, ny, target_area_id)
                    else
                        self.core:set_connected_id(nx, ny, target_area_id)
                    end
                end
            end
        end
    else
        -- 如果只有一个或没有邻近区域，直接设置当前点的区域ID
        local target_area_id = area_ids[1] or (self.core:get_max_connected_id() + 1)
        if set_area_id then
            set_area_id(x, y, target_area_id)
        else
            self.core:set_connected_id(x, y, target_area_id)
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
    if not self:is_obstacle(center_pos) then
        return
    end
    local cell = pos2cell(self, center_pos)
    ---@class LuaNavigationPortal
    local portal = {
        pos = center_pos, ---@type LuaNavigationPosition
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
        if not joint.disabled then
            local distance = calc_distance(node.pos, joint.pos)
            node.connected[joint] = { { node.pos, joint.pos }, distance }
            joint.connected[node] = { { joint.pos, node.pos }, distance }
        end
    end
end

local function disconnect_to_area(area, node)
    for _, joint in pairs(area.joints) do
        node.connected[joint] = nil
        joint.connected[node] = nil
    end
end

local function merge_path(path1, path2)
    for i = 1, #path2 - 1 do
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
            t[#t + 1] = s
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
                if not node.disabled and not closed_set[node] and not open_set[node] then
                    add_to_open_set(node, cur_node)
                end
            end
        end

        if not dst_node.prev then
            return {}
        end
        local node_path = {} ---@type LuaNavigationNode[]
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

local DIR_OFFSET = { ---@type LuaNavigationPosition[] 顺时针方向
    { x = -1, y = -1 },
    { x = 0,  y = -1 },
    { x = 1,  y = -1 },
    { x = 1,  y = 0 },
    { x = 1,  y = 1 },
    { x = 0,  y = 1 },
    { x = -1, y = 1 },
    { x = -1, y = 0 },
}

---@param self LuaNavigation
---@param pos LuaNavigationPosition
---@param max_size number
local function find_nearest_joint(self, pos, max_size)
    local tmp_pos = { x = pos.x, y = pos.y }
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
