
#include "map.h"

void push_pos_to_path(Map* m, int pos) {
    if(m->path_len >= m->path_cap) {
        int old_cap = m->path_cap;
        m->path_cap *= 2;
        int* new_path = (int*) malloc(sizeof(int) * m->path_cap);
        memcpy(new_path, m->path, old_cap);
        free(m->path);
        m->path = new_path;
    }
    m->path[m->path_len++] = pos;
}