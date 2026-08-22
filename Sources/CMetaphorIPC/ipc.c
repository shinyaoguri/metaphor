#include "CMetaphorIPC.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <unistd.h>

int metaphor_shm_open_anon(void) {
    char name[32];
    for (int attempt = 0; attempt < 100; attempt++) {
        /* PSHMNAMLEN (31) に収まる決定的な名前。衝突したら連番で再試行する。 */
        snprintf(name, sizeof name, "/mp-%d-%d", (int)getpid(), attempt);
        int fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
        if (fd >= 0) {
            /* 名前は即座に捨てる。オブジェクトは fd（と mmap）で生きる。 */
            shm_unlink(name);
            return fd;
        }
        if (errno != EEXIST) {
            return -1;
        }
    }
    errno = EEXIST;
    return -1;
}

ssize_t metaphor_send_fd(int sock, int fd, const void *buf, size_t len) {
    struct iovec iov = { .iov_base = (void *)buf, .iov_len = len };
    struct msghdr msg;
    memset(&msg, 0, sizeof msg);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;

    char control[CMSG_SPACE(sizeof(int))];
    if (fd >= 0) {
        memset(control, 0, sizeof control);
        msg.msg_control = control;
        msg.msg_controllen = sizeof control;
        struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
        c->cmsg_level = SOL_SOCKET;
        c->cmsg_type = SCM_RIGHTS;
        c->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(c), &fd, sizeof(int));
    }
    return sendmsg(sock, &msg, 0);
}

ssize_t metaphor_recv_fd(int sock, void *buf, size_t cap, int *out_fd) {
    if (out_fd) {
        *out_fd = -1;
    }
    struct iovec iov = { .iov_base = buf, .iov_len = cap };
    struct msghdr msg;
    memset(&msg, 0, sizeof msg);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    char control[CMSG_SPACE(sizeof(int))];
    memset(control, 0, sizeof control);
    msg.msg_control = control;
    msg.msg_controllen = sizeof control;

    ssize_t n = recvmsg(sock, &msg, 0);
    if (n <= 0) {
        return n;
    }
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c != NULL; c = CMSG_NXTHDR(&msg, c)) {
        if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS
            && c->cmsg_len >= CMSG_LEN(sizeof(int))) {
            int fd;
            memcpy(&fd, CMSG_DATA(c), sizeof(int));
            if (out_fd) {
                *out_fd = fd;
            } else {
                close(fd);
            }
            break;
        }
    }
    return n;
}
