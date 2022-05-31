
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
    printf("add pos %d\n", m->ipath[m->ipath_len - 1]);
}

void push_pos_to_fpath(Map* m, float fpos) {
    m->fpath_len++;
    if(m->fpath_len >= m->fpath_cap) {
        int old_cap = m->fpath_cap;
        m->fpath_cap *= 2;
        float* new_path = (float*)malloc(sizeof(float) * m->ipath_cap);
        memcpy(new_path, m->fpath, old_cap);
        free(m->fpath);
        m->fpath = new_path;
    }
    m->fpath[m->fpath_len - 1] = fpos;
    printf("add pos %f\n", m->fpath[m->fpath_len - 1]);
}