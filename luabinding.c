#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "fibheap.h"
#include "jps.h"
#include "map.h"
#include "smooth.h"

#ifdef __PRINT_DEBUG__
#define deep_print(format, ...) printf(format, ##__VA_ARGS__)
#else
#define deep_print(format, ...)
#endif

#define MT_NAME ("_nav_metatable")

static inline int getfield(lua_State* L, const char* f) {
    if (lua_getfield(L, -1, f) != LUA_TNUMBER) {
        return luaL_error(L, "invalid type %s", f);
    }
    int v = lua_tointeger(L, -1);
    lua_pop(L, 1);
    return v;
}

static inline int setobstacle(lua_State* L, struct map* m, int x, int y) {
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITSET(m->m, m->width * y + x);
    return 0;
}

static void push_path_to_istack(lua_State* L, struct map* m) {
    lua_newtable(L);
    int i, x, y;
    int num = 1;
    for (i = m->ipath_len - 1; i >= 0; i--) {
        pos2xy(m, m->ipath[i], &x, &y);
        printf("pos:%d x:%d y:%d\n", m->ipath[i], x, y);
        lua_newtable(L);
        lua_pushinteger(L, x);
        lua_rawseti(L, -2, 1);
        lua_pushinteger(L, y);
        lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, num++);
    }
}

static void push_fpos(lua_State* L, float fx, float fy, int num) {
    lua_newtable(L);
    lua_pushnumber(L, fx);
    lua_rawseti(L, -2, 1);
    lua_pushnumber(L, fy);
    lua_rawseti(L, -2, 2);
    lua_rawseti(L, -2, num);
}

static void push_path_to_fstack(lua_State* L,
                                struct map* m,
                                float fx1,
                                float fy1,
                                float fx2,
                                float fy2) {
    lua_newtable(L);
    int i, ix, iy;
    float fx, fy;
    int num = 1;
    if (m->ipath_len < 2) {
        return;
    }

    push_fpos(L, fx1, fy1, num++);
    pos2xy(m, m->ipath[m->ipath_len - 2], &ix, &iy);

    if (!check_line_walkable(m, fx1, fy1, ix + 0.5, iy + 0.5)) {
        // 插入起点到第二个路点间的拐点
        fx = fx1 > ix + 0.5 ? floor(fx1) : ceil(fx1);
        fy = fy1 > iy + 0.5 ? floor(fy1) : ceil(fy1);
        push_fpos(L, fx, fy, num++);
    }

    for (i = m->ipath_len - 1; i >= 2; i--) {
        pos2xy(m, m->ipath[i], &ix, &iy);
        push_fpos(L, ix, iy, num++);
    }

    if (m->ipath_len > 2) {
        // 插入倒数第二个路点到终点间的拐点
        pos2xy(m, m->ipath[1], &ix, &iy);
        if (!check_line_walkable(m, ix + 0.5, iy + 0.5, fx2, fy2)) {
            fx = fx2 < (float)ix + 0.5 ? floor(fx2) : ceil(fx2);
            fy = fy2 < (float)iy + 0.5 ? floor(fy2) : ceil(fy2);
            push_fpos(L, fx, fy, num++);
        }
    }
    push_fpos(L, fx2, fy2, num++);
}

static int insert_mid_jump_point(struct map* m, int cur, int father) {
    int w = m->width;
    int dx = cur % w - father % w;
    int dy = cur / w - father / w;
    if (dx == 0 || dy == 0) {
        return 0;
    }
    if (dx < 0) {
        dx = -dx;
    }
    if (dy < 0) {
        dy = -dy;
    }
    if (dx == dy) {
        return 0;
    }
    int span = dx;
    if (dy < dx) {
        span = dy;
    }
    int mx = 0, my = 0;
    if (cur % w < father % w && cur / w < father / w) {
        mx = father % w - span;
        my = father / w - span;
    } else if (cur % w < father % w && cur / w > father / w) {
        mx = father % w - span;
        my = father / w + span;
    } else if (cur % w > father % w && cur / w < father / w) {
        mx = father % w + span;
        my = father / w - span;
    } else if (cur % w > father % w && cur / w > father / w) {
        mx = father % w + span;
        my = father / w + span;
    }
#ifdef __RECORD_PATH__
    int len = m->width * m->height;
    BITSET(m->m, len * 2 + mx + my * w);
#endif
    push_pos_to_ipath(m, xy2pos(m, mx, my));
    return 1;
}

static void flood_mark(struct map* m,
                       int* visited,
                       int pos,
                       int connected_num,
                       int limit) {
    if (visited[pos]) {
        return;
    }
    visited[pos] = 1;
    m->connected[pos] = connected_num;
#define FLOOD(n)                                               \
    do {                                                       \
        if (check_in_map_pos(n, limit) && !BITTEST(m->m, n)) { \
            flood_mark(m, visited, n, connected_num, limit);   \
        }                                                      \
    } while (0);
    FLOOD(pos - 1);
    FLOOD(pos + 1);
    FLOOD(pos - m->width);
    FLOOD(pos + m->width);
#undef FLOOD
}

static int lnav_add_block(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITSET(m->m, m->width * y + x);
    return 0;
}

static int lnav_blockset(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);
    int i = 1;
    while (lua_geti(L, -1, i) == LUA_TTABLE) {
        lua_geti(L, -1, 1);
        int x = lua_tointeger(L, -1);
        lua_geti(L, -2, 2);
        int y = lua_tointeger(L, -1);
        setobstacle(L, m, x, y);
        lua_pop(L, 3);
        ++i;
    }
    return 0;
}

static int lnav_clear_block(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITCLEAR(m->m, m->width * y + x);
    return 0;
}

static int lnav_clear_allblock(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    int i;
    for (i = 0; i < m->width * m->height; i++) {
        BITCLEAR(m->m, i);
    }
    return 0;
}

static int lnav_mark_connected(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    int len = m->width * m->height;
    if (!m->mark_connected) {
        m->connected = (int*)malloc(len * sizeof(int));
        m->mark_connected = 1;
    }
    memset(m->connected, 0, len * sizeof(int));
    int i, connected_num = 0;
    int limit = m->width * m->height;
    int visited[len];
    memset(visited, 0, len * sizeof(int));
    for (i = 0; i < len; i++) {
        if (!visited[i] && !BITTEST(m->m, i)) {
            connected_num++;
            flood_mark(m, visited, i, connected_num, limit);
        }
    }
    return 0;
}

static int lnav_dump_connected(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    printf("dump map connected state!!!!!!\n");
    if (!m->mark_connected) {
        printf("have not mark connected.\n");
        return 0;
    }
    int i;
    for (i = 0; i < m->width * m->height; i++) {
        int mark = m->connected[i];
        if (mark > 0) {
            printf("%d ", mark);
        } else {
            printf("* ");
        }
        if ((i + 1) % m->width == 0) {
            printf("\n");
        }
    }
    return 0;
}

static int lnav_dump(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    printf("dump map state!!!!!!\n");
    int i, pos;
#ifdef __RECORD_PATH__
    int len = m->width * m->height;
#endif
    char s[m->width * 2 + 2];
    for (pos = 0, i = 0; i < m->width * m->height; i++) {
        if (i > 0 && i % m->width == 0) {
            s[pos - 1] = '\0';
            printf("%s\n", s);
            pos = 0;
        }
        int mark = 0;
        if (BITTEST(m->m, i)) {
            s[pos++] = '*';
            mark = 1;
        } else {
#ifdef __RECORD_PATH__
            if (BITTEST(m->m, len * 2 + i)) {
                s[pos++] = '0';
                mark = 1;
            }
#endif
        }
        if (i == m->start) {
            s[pos++] = 'S';
            mark = 1;
        }
        if (i == m->end) {
            s[pos++] = 'E';
            mark = 1;
        }
        if (mark) {
            s[pos++] = ' ';
        } else {
            s[pos++] = '.';
            s[pos++] = ' ';
        }
    }
    s[pos - 1] = '\0';
    printf("%s\n", s);
    return 0;
}

static int gc(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    free(m->comefrom);
    free(m->open_set_map);
    if (m->mark_connected) {
        free(m->connected);
    }
    return 0;
}

static void form_ipath(struct map* m, int last) {
    int pos = last;
    m->ipath_len = 0;
#ifdef __RECORD_PATH__
    int len = m->width * m->height;
#endif
    while (m->comefrom[pos] != -1) {
#ifdef __RECORD_PATH__
        BITSET(m->m, len * 2 + pos);
#endif
        push_pos_to_ipath(m, pos);
        insert_mid_jump_point(m, pos, m->comefrom[pos]);
        pos = m->comefrom[pos];
    }
    push_pos_to_ipath(m, m->start);
}

static int lnav_check_line_walkable(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    float x1 = luaL_checknumber(L, 2);
    float y1 = luaL_checknumber(L, 3);
    float x2 = luaL_checknumber(L, 4);
    float y2 = luaL_checknumber(L, 5);
    lua_pushboolean(L, check_line_walkable(m, x1, y1, x2, y2));
    return 1;
}

static int lnav_find_path(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    float fx1 = luaL_checknumber(L, 2);
    float fy1 = luaL_checknumber(L, 3);
    int x = fx1;
    int y = fy1;
    if (check_in_map(x, y, m->width, m->height)) {
        m->start = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    float fx2 = luaL_checknumber(L, 4);
    float fy2 = luaL_checknumber(L, 5);
    x = fx2;
    y = fy2;
    if (check_in_map(x, y, m->width, m->height)) {
        m->end = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    if (BITTEST(m->m, m->start)) {
        luaL_error(L, "start pos(%d,%d) is in block", m->start % m->width,
                   m->start / m->width);
        return 0;
    }
    if (BITTEST(m->m, m->end)) {
        luaL_error(L, "end pos(%d,%d) is in block", m->end % m->width,
                   m->end / m->width);
        return 0;
    }
    int start_pos = jps_find_path(m);
    if (start_pos >= 0) {
        form_ipath(m, start_pos);
        smooth_path(m);
        push_path_to_fstack(L, m, fx1, fy1, fx2, fy2);
        return 1;
    }
    return 0;
}

static int lnav_find_path_by_grid(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (check_in_map(x, y, m->width, m->height)) {
        m->start = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    x = luaL_checkinteger(L, 4);
    y = luaL_checkinteger(L, 5);
    if (check_in_map(x, y, m->width, m->height)) {
        m->end = m->width * y + x;
    } else {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    if (BITTEST(m->m, m->start)) {
        luaL_error(L, "start pos(%d,%d) is in block", m->start % m->width,
                   m->start / m->width);
        return 0;
    }
    if (BITTEST(m->m, m->end)) {
        luaL_error(L, "end pos(%d,%d) is in block", m->end % m->width,
                   m->end / m->width);
        return 0;
    }
    int start_pos = jps_find_path(m);
    if (start_pos >= 0) {
        form_ipath(m, start_pos);
        smooth_path(m);
        push_path_to_istack(L, m);
        return 1;
    }
    return 0;
}

static int lmetatable(lua_State* L) {
    if (luaL_newmetatable(L, MT_NAME)) {
        luaL_Reg l[] = {{"add_block", lnav_add_block},
                        {"add_blockset", lnav_blockset},
                        {"clear_block", lnav_clear_block},
                        {"clear_allblock", lnav_clear_allblock},
                        {"find_path_by_grid", lnav_find_path_by_grid},
                        {"find_path", lnav_find_path},
                        {"check_line_walkable", lnav_check_line_walkable},
                        {"mark_connected", lnav_mark_connected},
                        {"dump_connected", lnav_dump_connected},
                        {"dump", lnav_dump},
                        {NULL, NULL}};
        luaL_newlib(L, l);
        lua_setfield(L, -2, "__index");

        lua_pushcfunction(L, gc);
        lua_setfield(L, -2, "__gc");
    }
    return 1;
}

static int lnewmap(lua_State* L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);
    int width = getfield(L, "w");
    int height = getfield(L, "h");
    lua_assert(width > 0 && height > 0);
    int len = width * height;
#ifdef __RECORD_PATH__
    int map_men_len = (BITSLOT(len) + 1) * 3;
#else
    int map_men_len = (BITSLOT(len) + 1) * 2;
#endif
    Map* m = lua_newuserdata(L, sizeof(Map) + map_men_len * sizeof(m->m[0]));
    m->width = width;
    m->height = height;
    m->start = -1;
    m->end = -1;
    m->mark_connected = 0;
    m->comefrom = (int*)malloc(len * sizeof(int));
    m->ipath_cap = 2;
    m->ipath_len = 0;
    m->ipath = (int*)malloc(m->ipath_cap * sizeof(int));
    m->open_set_map =
        (struct heap_node**)malloc(len * sizeof(struct heap_node*));
    memset(m->m, 0, map_men_len * sizeof(m->m[0]));
    if (lua_getfield(L, 1, "obstacle") == LUA_TTABLE) {
        int i = 1;
        while (lua_geti(L, -1, i) == LUA_TTABLE) {
            lua_geti(L, -1, 1);
            int x = lua_tointeger(L, -1);
            lua_geti(L, -2, 2);
            int y = lua_tointeger(L, -1);
            setobstacle(L, m, x, y);
            lua_pop(L, 3);
            ++i;
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    lmetatable(L);
    lua_setmetatable(L, -2);
    return 1;
}

LUAMOD_API int luaopen_navigation(lua_State* L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"new", lnewmap},
        {NULL, NULL},
    };
    luaL_newlib(L, l);
    return 1;
}