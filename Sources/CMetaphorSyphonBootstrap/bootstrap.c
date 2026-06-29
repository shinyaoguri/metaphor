#include "CMetaphorSyphonBootstrap.h"

/*
 * MetaphorSyphon 側で @_cdecl("metaphor_syphon_register") として定義される Swift 関数。
 * プロセス起動時（このオブジェクトがリンクされている限り）に呼び出し、出力ファクトリを
 * MetaphorOutputRegistry へ登録する。これにより利用者が MetaphorSyphon を明示参照せずとも
 * （アンブレラ経由のリンクだけで）Syphon 出力が透過的に有効化される。
 */
extern void metaphor_syphon_register(void);

__attribute__((constructor))
static void cmetaphor_syphon_bootstrap_init(void) {
    metaphor_syphon_register();
}

void cmetaphor_syphon_bootstrap_touch(void) {}
