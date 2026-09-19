#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int has_value(const char *name) {
    const char *value = getenv(name);
    return value != NULL && value[0] != '\0';
}

static int reopen_through_steam(void) {
    const char *open_path = "/usr/bin/open";
    char *const open_argv[] = {
        (char *)open_path,
        (char *)"steam://rungameid/646570",
        NULL
    };
    pid_t child = 0;
    int status = 0;
    int error = posix_spawn(&child, open_path, NULL, NULL, open_argv, environ);
    if (error != 0) {
        fprintf(stderr, "SlayTheSpire: could not ask Steam to launch the game: %s\n",
                strerror(error));
        return 1;
    }
    if (waitpid(child, &status, 0) < 0) {
        fprintf(stderr, "SlayTheSpire: could not wait for Steam launch request: %s\n",
                strerror(errno));
        return 1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static char *resources_directory(void) {
    uint32_t size = PATH_MAX;
    char stack_path[PATH_MAX];
    char *executable_path = stack_path;

    if (_NSGetExecutablePath(executable_path, &size) != 0) {
        executable_path = malloc(size);
        if (executable_path == NULL || _NSGetExecutablePath(executable_path, &size) != 0) {
            free(executable_path == stack_path ? NULL : executable_path);
            return NULL;
        }
    }

    char resolved[PATH_MAX];
    const char *usable_path = realpath(executable_path, resolved) != NULL
        ? resolved : executable_path;
    char *directory = strdup(usable_path);
    if (executable_path != stack_path) {
        free(executable_path);
    }
    if (directory == NULL) {
        return NULL;
    }

    char *slash = strrchr(directory, '/');
    if (slash == NULL) {
        free(directory);
        return NULL;
    }
    *slash = '\0';

    char candidate[PATH_MAX];
    if (snprintf(candidate, sizeof(candidate), "%s/../Resources", directory)
            >= (int)sizeof(candidate)) {
        free(directory);
        return NULL;
    }
    free(directory);

    char *resources = malloc(PATH_MAX);
    if (resources == NULL) {
        return NULL;
    }
    if (realpath(candidate, resources) == NULL) {
        free(resources);
        return NULL;
    }
    return resources;
}

int main(int argc, char **argv) {
    if (!has_value("SteamAppId") && !has_value("SteamGameId")) {
        return reopen_through_steam();
    }

    char *resources = resources_directory();
    if (resources == NULL) {
        fprintf(stderr, "SlayTheSpire: could not locate the app Resources directory\n");
        return 1;
    }
    if (chdir(resources) != 0) {
        fprintf(stderr, "SlayTheSpire: could not enter %s: %s\n",
                resources, strerror(errno));
        free(resources);
        return 1;
    }

    char java_path[PATH_MAX];
    if (snprintf(java_path, sizeof(java_path), "%s/jre/bin/java", resources)
            >= (int)sizeof(java_path)) {
        fprintf(stderr, "SlayTheSpire: bundled Java path is too long\n");
        free(resources);
        return 1;
    }

    char *fixed[] = {
        java_path,
        (char *)"-Xdock:icon=icons.icns",
        (char *)"-Xdock:name=Slay the Spire",
        (char *)"-Xmx1G",
        (char *)"-Dsun.java2d.dpiaware=true",
        (char *)"-Dorg.lwjgl.opengl.Display.enableHighDPI=true",
        (char *)"-jar",
        (char *)"desktop-1.0.jar"
    };
    const size_t fixed_count = sizeof(fixed) / sizeof(fixed[0]);
    const size_t forwarded_count = argc > 1 ? (size_t)(argc - 1) : 0;
    char **java_argv = calloc(fixed_count + forwarded_count + 1, sizeof(char *));
    if (java_argv == NULL) {
        fprintf(stderr, "SlayTheSpire: could not allocate Java argument list\n");
        free(resources);
        return 1;
    }
    for (size_t i = 0; i < fixed_count; i++) {
        java_argv[i] = fixed[i];
    }
    for (size_t i = 0; i < forwarded_count; i++) {
        java_argv[fixed_count + i] = argv[i + 1];
    }

    execv(java_path, java_argv);
    fprintf(stderr, "SlayTheSpire: could not start bundled Java: %s\n", strerror(errno));
    free(java_argv);
    free(resources);
    return 127;
}
