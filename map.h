#ifndef __MAP__
#define __MAP__ 0

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"


#ifdef __PRINT_DEBUG__
#define deep_print(format, ...) printf(format, ##__VA_ARGS__)
#else
#define deep_print(format, ...)
#endif

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
    int* comefrom;
    char mark_connected;
    int* connected;

    struct heap_node** open_set_map;
    /*
        [map] | [close_set] | [path]
    */
    int* jump_path; // find path by jps_find_path
    int* smooth_path; // smooth jump_path;
    int jump_len;
    int smooth_len;
    char m[0];

};

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

inline int map_walkable(struct map* m, int pos) {
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

inline void pos2xy(struct map* m, int pos, int* x, int* y) {
    *x = pos % m->width;
    *y = pos / m->width; 
}

inline int xy2pos(struct map* m, int x, int y) {
    return m->width * y + x;
}

#endif /* __MAP__ */