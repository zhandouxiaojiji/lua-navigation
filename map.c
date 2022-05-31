
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
    printf("add pos to ipath %d\n", m->ipath[m->ipath_len - 1]);
}