
#include "map.h"

void push_pos_to_ipath(Map* m, int ipos) {
    m->ipath_len++;
    if (m->ipath_len > m->ipath_cap) {
        int* old_path = m->ipath;
        m->ipath_cap *= 2;
        m->ipath = (int*)malloc(sizeof(int) * m->ipath_cap);
        memcpy(m->ipath, old_path, sizeof(int) * (m->ipath_len - 1));
        free(old_path);
    }
    m->ipath[m->ipath_len - 1] = ipos;
    // printf("add pos to ipath %d\n", m->ipath[m->ipath_len - 1]);
}

void init_map(Map* m, int width, int height, int map_men_len) {
    int len = width * height;
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
}