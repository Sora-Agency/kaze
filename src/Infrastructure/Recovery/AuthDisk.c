// Adapted from LibreRescateNativo (MIT); see Recovery/LibreRescate-LICENSE.txt.
#include "AuthDisk.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;

int kaze_authorize_readonly(const char *device, int (*cancelled)(void *), void *context) {
    if (!device || strncmp(device, "/dev/rdisk", 10) != 0) { errno = EINVAL; return -1; }
    const char *suffix = device + 10;
    if (*suffix < '0' || *suffix > '9') { errno = EINVAL; return -1; }
    while (*suffix >= '0' && *suffix <= '9') suffix++;
    if (*suffix == 's') {
        suffix++;
        if (*suffix < '0' || *suffix > '9') { errno = EINVAL; return -1; }
        while (*suffix >= '0' && *suffix <= '9') suffix++;
    }
    if (*suffix) { errno = EINVAL; return -1; }
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) return -1;
    fcntl(sockets[0], F_SETFD, FD_CLOEXEC);
    fcntl(sockets[1], F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, sockets[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, sockets[0]);
    posix_spawn_file_actions_addclose(&actions, sockets[1]);
    // Explicit O_RDONLY; no shell, password handling or write authorization.
    char *arguments[] = {"authopen", "-stdoutpipe", "-o", "0", (char *)device, NULL};
    pid_t child;
    int spawned = posix_spawn(&child, "/usr/libexec/authopen", &actions, NULL, arguments, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(sockets[1]);
    if (spawned) { close(sockets[0]); errno = spawned; return -1; }
    int descriptor = -1;
    struct pollfd pollfd = {.fd = sockets[0], .events = POLLIN};
    for (int tick = 0; tick < 1200; tick++) {
        if (cancelled && cancelled(context)) break;
        int ready = poll(&pollfd, 1, 100);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) continue;
        char byte;
        struct iovec iov = {.iov_base = &byte, .iov_len = 1};
        union { struct cmsghdr header; char bytes[CMSG_SPACE(sizeof(int))]; } ancillary;
        memset(&ancillary, 0, sizeof(ancillary));
        struct msghdr message = {0};
        message.msg_iov = &iov; message.msg_iovlen = 1;
        message.msg_control = ancillary.bytes; message.msg_controllen = sizeof(ancillary.bytes);
        if (recvmsg(sockets[0], &message, 0) > 0) {
            for (struct cmsghdr *control = CMSG_FIRSTHDR(&message); control; control = CMSG_NXTHDR(&message, control)) {
                if (control->cmsg_level == SOL_SOCKET && control->cmsg_type == SCM_RIGHTS &&
                    control->cmsg_len >= CMSG_LEN(sizeof(int))) { memcpy(&descriptor, CMSG_DATA(control), sizeof(int)); break; }
            }
        }
        break;
    }
    close(sockets[0]);
    int status = 0, finished = 0;
    for (int tick = 0; tick < 50; tick++) {
        if (waitpid(child, &status, WNOHANG) == child) { finished = 1; break; }
        if (cancelled && cancelled(context)) break;
        usleep(10000);
    }
    if (!finished) { kill(child, SIGKILL); while (waitpid(child, &status, 0) < 0 && errno == EINTR) {} }
    struct stat received, expected;
    if (descriptor < 0 || !finished || !WIFEXITED(status) || WEXITSTATUS(status) ||
        (cancelled && cancelled(context)) || (fcntl(descriptor, F_GETFL) & O_ACCMODE) != O_RDONLY ||
        fstat(descriptor, &received) || stat(device, &expected) || !S_ISCHR(received.st_mode) || received.st_rdev != expected.st_rdev) {
        if (descriptor >= 0) close(descriptor);
        errno = EACCES; return -1;
    }
    fcntl(descriptor, F_SETFD, FD_CLOEXEC);
    return descriptor;
}
