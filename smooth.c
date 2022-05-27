
#include "smooth.h"
#include "map.h"

void smooth_path(struct map* m) {}

int check_line_walkable(struct map* m, float x1, float y1, float x2, float y2) {
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
