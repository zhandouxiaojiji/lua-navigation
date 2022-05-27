#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <string.h>
#include <stdlib.h>
#include <limits.h>
#include "fibheap.h"

#ifdef __PRINT_DEBUG__
#define deep_print(format,...) printf(format, ##__VA_ARGS__)
#else
#define deep_print(format,...)
#endif

#define MT_NAME ("_jps_search_metatable")

#define BITMASK(b) (1 << ((b) % CHAR_BIT))
#define BITSLOT(b) ((b) / CHAR_BIT)
#define BITSET(a, b) ((a)[BITSLOT(b)] |= BITMASK(b))
#define BITCLEAR(a, b) ((a)[BITSLOT(b)] &= ~BITMASK(b))
#define BITTEST(a, b) ((a)[BITSLOT(b)] & BITMASK(b))

struct map {
    int width;
    int height;
    int start;
    int end;
    int *comefrom;
    char mark_connected;
    int *connected;
    struct heap_node **open_set_map;
/*
    [map] | [close_set] | [path]
*/
    char m[0];
};

static inline int
getfield(lua_State *L, const char *f) {
    if (lua_getfield(L, -1, f) != LUA_TNUMBER) {
        return luaL_error(L, "invalid type %s", f);
    }
    int v = lua_tointeger(L, -1);
    lua_pop(L, 1);
    return v;
}

static inline int check_in_map(int x, int y, int w, int h) {
    return x >= 0 && y >= 0 && x < w && y < h;
}

static inline int check_in_map_pos(int pos, int limit) {
    return pos >= 0 && pos < limit;
}

static inline int
setobstacle(lua_State *L, struct map *m, int x, int y) {
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITSET(m->m, m->width * y + x);
    return 0;
}

static int
add_block(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITSET(m->m, m->width * y + x);
    return 0;
}

static int
add_blockset(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
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

static int
clear_block(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
    int x = luaL_checkinteger(L, 2);
    int y = luaL_checkinteger(L, 3);
    if (!check_in_map(x, y, m->width, m->height)) {
        luaL_error(L, "Position (%d,%d) is out of map", x, y);
    }
    BITCLEAR(m->m, m->width * y + x);
    return 0;
}

static int
clear_allblock(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
    int i;
    for (i = 0; i < m->width * m->height; i++) {
        BITCLEAR(m->m, i);
    }
    return 0;
}

static int
set_start(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
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

static int
set_end(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
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

static inline int compare(struct node_data *old, struct node_data *new)
{
    if (new->f_value < old->f_value) {
        return 1;
    }
    else {
        return -1;
    }
}

static int dist(int one, int two, int w) {
    int ex = one % w, ey = one / w;
    int px = two % w, py = two / w;
    int dx = ex - px, dy = ey - py;
    if (dx < 0) {
        dx = -dx;
    }
    if (dy < 0) {
        dy = -dy;
    }
    if (dx < dy) {
        return dx *  7 + (dy-dx) * 5;
    }
    else {
        return dy * 7 + (dx - dy) * 5;
    }
}

static struct node_data *construct(struct map *m, int pos, int g_value,
            unsigned char dir) {
    struct node_data *node = (struct node_data *)malloc(sizeof(struct node_data));
    node->pos = pos;
    node->g_value = g_value;
    node->f_value = g_value + dist(m->end, pos, m->width);
    node->dir = dir;
    return node;
}

static inline void push_table_to_stack(lua_State *L, int x, int y, int num) {
    lua_newtable(L);
    lua_pushinteger(L, x);
    lua_rawseti(L, -2, 1);
    lua_pushinteger(L, y);
    lua_rawseti(L, -2, 2);
    lua_rawseti(L, -2, num);
}

static int insert_mid_jump_point(lua_State *L, struct map *m, int cur,
            int father, int w, int num) {
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

static int
form_path(lua_State *L, int last, struct map *m) {
    int pos = last;
    lua_newtable(L);
    int num = 0;
    int x, y;
    int w = m->width;
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

#define NO_DIRECTION 8
#define FULL_DIRECTIONSET 255
#define EMPTY_DIRECTIONSET 0

// N, NE, E, SE, S, SW, W, NW
/*
   7  0  1
    \ | /
  6 -   - 2
    / | \
   5  4  3
*/

static void dir_add(unsigned char *dirs, unsigned char dir)
{
    *dirs |= (1 << dir);
}

static int dir_is_diagonal(unsigned char dir)
{
    return (dir % 2) != 0;
}

static inline int
map_walkable(int pos, int limit, struct map *m) {
    return check_in_map_pos(pos, limit) && !BITTEST(m->m, pos);
}

static int get_next_pos(int pos, unsigned char dir, int w, int h) {
    int x = pos % w;
    int y = pos / w;
    switch (dir) {
        case 0:
            y = y - 1;
            break;
        case 1:
            x = x + 1;
            y = y - 1;
            break;
        case 2:
            x = x + 1;
            break;
        case 3:
            x = x + 1;
            y = y + 1;
            break;
        case 4:
            y = y + 1;
            break;
        case 5:
            x = x - 1;
            y = y + 1;
            break;
        case 6:
            x = x - 1;
            break;
        case 7:
            x = x - 1;
            y = y - 1;
            break;
        default: return -1;
    }
    if (!check_in_map(x, y, w, h)) {
        return -1;
    }
    return x + y * w;
}

static inline int walkable(struct map *m, int pos, int cur_dir, int next_dir) {
    return map_walkable(
        get_next_pos(pos, (cur_dir + (next_dir)) % 8, m->width, m->height),
        m->width * m->height, m);
}

static unsigned char natural_dir(int pos, unsigned char cur_dir, struct map *m) {
    unsigned char dir_set = EMPTY_DIRECTIONSET;
    if (cur_dir == NO_DIRECTION) {
        return FULL_DIRECTIONSET;
    }
#ifdef __CONNER_SOLVE__
    if (dir_is_diagonal(cur_dir)) {
        if (!walkable(m, pos, cur_dir, 7)) {
            dir_add(&dir_set, (cur_dir + 1) % 8);
        } else if (!walkable(m, pos, cur_dir, 1)) {
            dir_add(&dir_set, (cur_dir + 7) % 8);
        } else {
            dir_add(&dir_set, cur_dir);
            dir_add(&dir_set, (cur_dir + 1) % 8);
            dir_add(&dir_set, (cur_dir + 7) % 8);
        }
    } else {
        dir_add(&dir_set, cur_dir);
    }
#else
    dir_add(&dir_set, cur_dir);
    if (dir_is_diagonal(cur_dir)) {
        dir_add(&dir_set, (cur_dir + 1) % 8);
        dir_add(&dir_set, (cur_dir + 7) % 8);
    }
#endif
    return dir_set;
}

static unsigned char force_dir(int pos, unsigned char cur_dir, struct map *m) {
    if (cur_dir == NO_DIRECTION) {
        return EMPTY_DIRECTIONSET;
    }
    unsigned char dir_set = EMPTY_DIRECTIONSET;
#define WALKABLE(n) walkable(m, pos, cur_dir, n)
#ifdef __CONNER_SOLVE__
    if (!dir_is_diagonal(cur_dir)) {
        if (WALKABLE(2) && !(WALKABLE(3))) {
            dir_add(&dir_set, (cur_dir + 2) % 8);
            if (WALKABLE(1)) {
                dir_add(&dir_set, (cur_dir + 1) % 8);
            }
        }
        if (WALKABLE(6) && !(WALKABLE(5))) {
            dir_add(&dir_set, (cur_dir + 6) % 8);
            if (WALKABLE(7)) {
                dir_add(&dir_set, (cur_dir + 7) % 8);
            }
        }
    }
#else
    if (dir_is_diagonal(cur_dir)) {
        if (WALKABLE(6) && !WALKABLE(5)) {
            dir_add(&dir_set, (cur_dir + 6) % 8);
        }
        if (WALKABLE(2) && !WALKABLE(3)) {
            dir_add(&dir_set, (cur_dir + 2) % 8);
        }
    } else {
        if (WALKABLE(1) && !WALKABLE(2)) {
            dir_add(&dir_set, (cur_dir + 1) % 8);
        }
        if (WALKABLE(7) && !WALKABLE(6)) {
            dir_add(&dir_set, (cur_dir + 7) % 8);
        }
    }
#endif
#undef WALKABLE
    return dir_set;
}

static unsigned char next_dir(unsigned char *dirs) {
    unsigned char dir;
    for (dir = 0 ; dir < 8 ; dir++) {
        char dirBit = 1 << dir;
        if (*dirs & dirBit) {
            *dirs ^= dirBit;
            return dir;
        }
    }
    return NO_DIRECTION;
}

static void put_in_open_set(struct heap *open_set, struct map *m, int pos,
            int len, struct node_data *node, unsigned char dir) {
    if (!BITTEST(m->m, len + pos)) {
        int ng_value = node->g_value + dist(pos, node->pos, m->width);
        struct heap_node *p = m->open_set_map[pos];
        if (!p) {
            m->comefrom[pos] = node->pos;
            struct node_data *test = construct(m, pos, ng_value, dir);
            m->open_set_map[pos] = fibheap_insert(open_set, test);
        } else if (p->data->g_value > ng_value) {
            m->comefrom[pos] = node->pos;
            p->data->f_value = p->data->f_value - (p->data->g_value - ng_value);
            p->data->g_value = ng_value;
            p->data->dir = dir;
            fibheap_decrease(open_set, p);
        }
    }
}

#ifdef __CONNER_SOLVE__
static int diagonal_obs(struct map *m, int pos, int new_pos, unsigned char dir) {
    switch (dir) {
        case 1:
            return BITTEST(m->m, pos + 1) || BITTEST(m->m, new_pos - 1);
        case 3:
            return BITTEST(m->m, pos + 1) || BITTEST(m->m, new_pos - 1);
        case 5:
            return BITTEST(m->m, pos - 1) || BITTEST(m->m, new_pos + 1);
        case 7:
            return BITTEST(m->m, pos - 1) || BITTEST(m->m, new_pos + 1);
        default: return 0;
    }
    return 0;
}
#endif

static int jump_prune(struct heap *open_set, int end, int pos, unsigned char dir,
            struct map *m, struct node_data *node) {
    int w = m->width;
    int h = m->height;
    int len = w * h;
    int next_pos = get_next_pos(pos, dir, w, h);
    if (!map_walkable(next_pos, len, m)) {
        return 0;
    }
#ifdef __CONNER_SOLVE__
    if (dir_is_diagonal(dir) && diagonal_obs(m, pos, next_pos, dir)) { // conner solve diagonal stop by obs
        return 0;
    }
#endif
    if (next_pos == end) {
        put_in_open_set(open_set, m, next_pos, len, node, dir);
        return 1;
    }
    if (force_dir(next_pos, dir, m) != EMPTY_DIRECTIONSET) {
        put_in_open_set(open_set, m, next_pos, len, node, dir);
        return 0;
    }
    if (dir_is_diagonal(dir)) {
        int i;
        i = jump_prune(open_set, end, next_pos, (dir + 7) % 8, m, node);
        if (i == 1) {
            return 1;
        }
        i = jump_prune(open_set, end, next_pos, (dir + 1) % 8, m, node);
        if (i == 1) {
            return 1;
        }
    }
    return jump_prune(open_set, end, next_pos, dir, m, node);
}

static int
find_path(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
    if (BITTEST(m->m, m->start)) {
        luaL_error(L, "start pos(%d,%d) is in block", m->start % m->width, m->start / m->width);
    }
    if (BITTEST(m->m, m->end)) {
        luaL_error(L, "end pos(%d,%d) is in block", m->end % m->width, m->end / m->width);
    }
    int len = m->width * m->height;
    memset(&m->m[BITSLOT(len) + 1], 0, (BITSLOT(len) + 1) * sizeof(m->m[0]));
    memset(m->comefrom, -1, len * sizeof(int));
    memset(m->open_set_map, 0, len * sizeof(struct heap_node *));
    if (m->start == m->end) {
        return form_path(L, m->end, m);
    }
    if (m->mark_connected && (m->connected[m->start] != m->connected[m->end])) {
        return 0;
    }
    struct heap *open_set = fibheap_init(len, compare);
    struct node_data *node = construct(m, m->start, 0, NO_DIRECTION);
    m->open_set_map[m->start] = fibheap_insert(open_set, node);;
    while ((node = fibheap_pop(open_set))) {
        m->open_set_map[node->pos] = NULL;
        BITSET(m->m, len + node->pos);
        if (node->pos == m->end) {
            fibheap_destroy(open_set);
            return form_path(L, node->pos, m);
        }
        unsigned char cur_dir = node->dir;
        unsigned char check_dirs = natural_dir(node->pos, cur_dir, m) | force_dir(node->pos, cur_dir, m);
        unsigned char dir = next_dir(&check_dirs);
        while (dir != NO_DIRECTION) {
            if (jump_prune(open_set, m->end, node->pos, dir, m, node) == 1) { // found end
                break;
            }
            dir = next_dir(&check_dirs);
        }
    }
    fibheap_destroy(open_set);
    return 0;
}

static void flood_mark(struct map *m, int *visited, int pos, int connected_num, int limit) {
    if (visited[pos]) {
        return;
    }
    visited[pos] = 1;
    m->connected[pos] = connected_num;
#define FLOOD(n) do { \
    if (check_in_map_pos(n, limit) && !BITTEST(m->m, n)) { \
        flood_mark(m, visited, n, connected_num, limit); \
    } \
} while(0);
    FLOOD(pos - 1);
    FLOOD(pos + 1);
    FLOOD(pos - m->width);
    FLOOD(pos + m->width);
#undef FLOOD
}

static int mark_connected(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
    int len = m->width * m->height;
    if (!m->mark_connected) {
        m->connected = (int *)malloc(len * sizeof(int));
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

static int
dump_connected(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
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

static int
dump(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
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

static int
gc(lua_State *L) {
    struct map *m = luaL_checkudata(L, 1, MT_NAME);
    free(m->comefrom);
    free(m->open_set_map);
    if (m->mark_connected) {
        free(m->connected);
    }
    return 0;
}

static int
lmetatable(lua_State *L) {
    if (luaL_newmetatable(L, MT_NAME)) {
        luaL_Reg l[] = {
            {"add_block", add_block},
            {"add_blockset", add_blockset},
            {"clear_block", clear_block},
            {"clear_allblock", clear_allblock},
            {"set_start", set_start},
            {"set_end", set_end},
            {"find_path", find_path},
            {"mark_connected", mark_connected},
            {"dump_connected", dump_connected},
            {"dump", dump},
            { NULL, NULL }
        };
        luaL_newlib(L, l);
        lua_setfield(L, -2, "__index");

        lua_pushcfunction(L, gc);
        lua_setfield(L, -2, "__gc");
    }
    return 1;
}

static int
lnewmap(lua_State *L) {
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
    struct map *m = lua_newuserdata(L, sizeof(struct map) + map_men_len * sizeof(m->m[0]));
    m->width = width;
    m->height = height;
    m->start = -1;
    m->end = -1;
    m->mark_connected = 0;
    m->comefrom = (int *)malloc(len * sizeof(int));
    m->open_set_map = (struct heap_node **)malloc(len * sizeof(struct heap_node *));
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

LUAMOD_API int
luaopen_navigation(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        { "new", lnewmap },
        { NULL, NULL },
    };
    luaL_newlib(L, l);
    return 1;
}
