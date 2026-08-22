#ifndef CMETAPHOR_IPC_H
#define CMETAPHOR_IPC_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * viewer frame IPC（CONTRACT.md 契約点 5）のための薄い C ラッパ。
 *
 * Swift からは `shm_open`（可変長引数）と `sendmsg` / `recvmsg` の `CMSG_*` マクロが
 * 呼べないので、その 3 点だけをここに置く。プロトコル（JSON Lines・slot の同期）は
 * Swift 側（Sources/MetaphorCore/Viewer/）が持つ。
 */

/*
 * 匿名の POSIX 共有メモリを作り、その fd を返す（失敗は -1、errno を設定）。
 *
 * shm_open(O_CREAT | O_EXCL, 0600) で一時的な名前（/mp-<pid>-<n>）を作り、**即座に
 * shm_unlink** する。以後オブジェクトは fd だけで生き、fd を持つプロセス以外から
 * 到達できない（名前の上限 31 文字・leak した名前の掃除・列挙不可、の制約が消える）。
 * サイズは呼び出し側が ftruncate で 1 回だけ決める（macOS では 2 回目が EINVAL）。
 */
int metaphor_shm_open_anon(void);

/*
 * buf の len byte を sock へ送る sendmsg に、fd を SCM_RIGHTS で添える。
 * 戻り値は sendmsg のもの（送ったバイト数、失敗は -1）。fd < 0 なら付けずに送る。
 */
ssize_t metaphor_send_fd(int sock, int fd, const void *buf, size_t len);

/*
 * sock から最大 cap byte を buf へ受け取る（recvmsg）。SCM_RIGHTS で fd が届いていれば
 * *out_fd に入れ、無ければ -1 を入れる。戻り値は recvmsg のもの（0 = EOF、-1 = 失敗）。
 */
ssize_t metaphor_recv_fd(int sock, void *buf, size_t cap, int *out_fd);

#ifdef __cplusplus
}
#endif

#endif /* CMETAPHOR_IPC_H */
