#ifndef KAZE_AUTH_DISK_H
#define KAZE_AUTH_DISK_H
int kaze_authorize_readonly(const char *device, int (*cancelled)(void *), void *context);
#endif
