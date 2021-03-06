#ifndef __MAP__
#define __MAP__ 0

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#define BITMASK(b) (1 << ((b) % CHAR_BIT))
#define BITSLOT(b) ((b) / CHAR_BIT)
#define BITSET(a, b) ((a)[BITSLOT(b)] |= BITMASK(b))
#define BITCLEAR(a, b) ((a)[BITSLOT(b)] &= ~BITMASK(b))
#define BITTEST(a, b) ((a)[BITSLOT(b)] & BITMASK(b))

typedef struct map {
    int width;
    int height;
    int start;
    int end;
    int* comefrom;
    char mark_connected;
    int* connected;

    struct heap_node** open_set_map;
    /*
        [map] | [close_set] | [path]
    */
    
    int* ipath; // 整型路点，锚点为格子中心
    int ipath_len;
    int ipath_cap;
    
    char m[0];

} Map;

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

inline void dir_add(unsigned char* dirs, unsigned char dir) {
    *dirs |= (1 << dir);
}

inline int dir_is_diagonal(unsigned char dir) {
    return (dir % 2) != 0;
}

inline int check_in_map(int x, int y, int w, int h) {
    return x >= 0 && y >= 0 && x < w && y < h;
}

inline int check_in_map_pos(int pos, int limit) {
    return pos >= 0 && pos < limit;
}

inline int map_walkable(Map* m, int pos) {
    return check_in_map_pos(pos, m->width * m->height) && !BITTEST(m->m, pos);
}

inline int dist(int one, int two, int w) {
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
        return dx * 7 + (dy - dx) * 5;
    } else {
        return dy * 7 + (dx - dy) * 5;
    }
}

inline void pos2xy(Map* m, int pos, int* x, int* y) {
    *x = pos % m->width;
    *y = pos / m->width;
}

inline int xy2pos(Map* m, int x, int y) {
    return m->width * y + x;
}

void push_pos_to_ipath(Map* m, int pos);
void init_map(Map* m, int width, int height, int map_men_len);

#endif /* __MAP__ */
