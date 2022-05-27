#ifndef __SMOOTH_H__
#define __SMOOTH_H__ 0

#include "map.h"

int check_line_walkable(struct map *m, float x1, float y1, float x2, float y2);
void smooth_path(struct map *m);

#endif /* __SMOOTH_H__ */