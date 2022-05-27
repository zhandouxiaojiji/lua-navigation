#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include "fibheap.h"
#include "jps.h"
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#ifdef __PRINT_DEBUG__
#define deep_print(format, ...) printf(format, ##__VA_ARGS__)
#else
#define deep_print(format, ...)
#endif

#define MT_NAME ("_jps_search_metatable")

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

static inline void push_table_to_stack(lua_State* L, int x, int y, int num) {
    lua_newtable(L);
    lua_pushinteger(L, x);
    lua_rawseti(L, -2, 1);
    lua_pushinteger(L, y);
    lua_rawseti(L, -2, 2);
    lua_rawseti(L, -2, num);
}

static int insert_mid_jump_point(lua_State* L,
                                 struct map* m,
                                 int cur,
                                 int father,
                                 int w,
                                 int num) {
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
    push_table_to_stack(L, mx, my, num + 1);
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

static int lnav_set_start(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    int pos = m->width * y + x;
    if (BITTEST(m->m, pos)) {
        luaL_error(L, "Position (%d,%d) is in block", x, y);
    }
    m->start = pos;
    return 0;
}

static int lnav_set_end(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    int pos = m->width * y + x;
    if (BITTEST(m->m, pos)) {
        luaL_error(L, "Position (%d,%d) is in block", x, y);
    }
    m->end = pos;
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

static int form_path(lua_State* L, int last, struct map* m) {
    lua_newtable(L);
    int num = 0;
    int x, y;
    int w = m->width;
    int pos = m->start;
    x = pos % w;
    y = pos / w;
    push_table_to_stack(L, x, y, ++num);
    pos = last;
#ifdef __RECORD_PATH__
    int len = m->width * m->height;
#endif
    while (m->comefrom[pos] != -1) {
#ifdef __RECORD_PATH__
        BITSET(m->m, len * 2 + pos);
#endif
        x = pos % w;
        y = pos / w;
        push_table_to_stack(L, x, y, ++num);
        num += insert_mid_jump_point(L, m, pos, m->comefrom[pos], w, num);
        pos = m->comefrom[pos];
    }
    return 1;
}

static int lnav_find_path(lua_State* L) {
    struct map* m = luaL_checkudata(L, 1, MT_NAME);
    if (BITTEST(m->m, m->start)) {
        luaL_error(L, "start pos(%d,%d) is in block", m->start % m->width,
                   m->start / m->width);
    }
    if (BITTEST(m->m, m->end)) {
        luaL_error(L, "end pos(%d,%d) is in block", m->end % m->width,
                   m->end / m->width);
    }
    int start_pos = jps_find_path(m);
    if (start_pos >= 0) {
        return form_path(L, start_pos, m);
    }
    return 0;
}

static int lmetatable(lua_State* L) {
    if (luaL_newmetatable(L, MT_NAME)) {
        luaL_Reg l[] = {{"add_block", lnav_add_block},
                        {"add_blockset", lnav_blockset},
                        {"clear_block", lnav_clear_block},
                        {"clear_allblock", lnav_clear_allblock},
                        {"set_start", lnav_set_start},
                        {"set_end", lnav_set_end},
                        {"find_path", lnav_find_path},
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
    struct map* m =
        lua_newuserdata(L, sizeof(struct map) + map_men_len * sizeof(m->m[0]));
    m->width = width;
    m->height = height;
    m->start = -1;
    m->end = -1;
    m->mark_connected = 0;
    m->comefrom = (int*)malloc(len * sizeof(int));
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