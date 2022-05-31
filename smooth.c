
#include "smooth.h"
#include "map.h"

int check_line_walkable(Map* m, float x1, float y1, float x2, float y2) {
    if (!map_walkable(m, xy2pos(m, (int)x1, (int)y1)) ||
        !map_walkable(m, xy2pos(m, (int)x2, (int)y2))) {
        return 0;
    }
    float k = (y2 - y1) / (x2 - x1);

    int min_x = x1 < x2 ? (int)x1 : (int)x2;
    int max_x = x1 < x2 ? (int)x2 : (int)x1;
    int min_y = y1 < y2 ? (int)y1 : (int)y2;
    int max_y = x1 < x2 ? (int)y2 : (int)y1;

    int x, y;
    for (x = min_x + 1; x < max_x; ++x) {
        y = (int)(k * ((float)x - x1) + y1);
        if (!map_walkable(m, xy2pos(m, x, y))) {
            return 0;
        }
    }

    for (y = min_y + 1; y < max_y; ++y) {
        x = (int)((y - y1) / k + x1);
        if (!map_walkable(m, xy2pos(m, x, y))) {
            return 0;
        }
    }

    return 1;
}

static void smooth_start_and_end(Map* m, float fx1, float fy1, float fx2, float fy2) {
    if (m->ipath_len < 2) {
        return;
    }
    int ix, iy;
    float fx, fy;
    pos2xy(m, m->ipath[1], &ix, &iy);
    fx = ix + 0.5;
    fy = iy + 0.5;
    if (check_line_walkable(m, fx1, fy1, fx, fy)){
        
    }
}

void smooth_path(Map* m) {
    int x1, y1, x2, y2;
    for (int i = m->ipath_len - 1; i >= 0; i--) {
        for (int j = 0; j <= i - 1; j++) {
            pos2xy(m, m->ipath[i], &x1, &y2);
            pos2xy(m, m->ipath[j], &x2, &y2);
            printf("check (%d)%d <=> (%d)%d\n", i, m->ipath[i], j, m->ipath[j]);
            if (check_line_walkable(m, x1 + 0.5, y1 + 0.5, x2 + 0.5,
                                    y2 + 0.5)) {
                int offset = i - j - 1;
                for (int k = i - 1; k >= j + 1; k--) {
                    m->ipath[k] = m->ipath[k + offset];
                    printf("%d <= %d\n", k, k + offset);
                }
                m->ipath_len -= offset;
                i = j;
                break;
            }
        }
    }
}
