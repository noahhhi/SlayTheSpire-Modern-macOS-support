#include <dlfcn.h>
#include <stdio.h>

static int load(const char *path) {
    void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        fprintf(stderr, "dlopen failed for %s: %s\n", path, dlerror());
        return 1;
    }
    printf("loaded %s\n", path);
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s libsteam_api libsteamworks4j\n", argv[0]);
        return 2;
    }
    return load(argv[1]) || load(argv[2]);
}
