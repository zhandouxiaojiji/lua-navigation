
#include "map.h"

void push_pos_to_ipath(Map* m, int ipos) {
    m->ipath_len++;
    if (m->ipath_len >= m->ipath_cap) {
        int old_cap = m->ipath_cap;
        m->ipath_cap *= 2;
        int* new_path = (int*)malloc(sizeof(int) * m->ipath_cap);
        memcpy(new_path, m->ipath, old_cap);
        free(m->ipath);
        m->ipath = new_path;
    }
    m->ipath[m->ipath_len - 1] = ipos;
    printf("add pos to ipath %d\n", m->ipath[m->ipath_len - 1]);
}