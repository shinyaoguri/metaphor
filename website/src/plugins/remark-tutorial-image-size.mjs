import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { visit } from 'unist-util-visit';

/**
 * チュートリアル本文の Gyazo 画像に、台帳が持っている縦横を焼き込む。
 *
 * 画像の実体は Gyazo にあり、本文は絶対 URL で指している（ADR-0010）。Astro は
 * リモート画像の縦横が分からないと `inferSize` を立て、**ビルドのたびに画像ごと
 * 1 回ずつ寸法を取りに行く**（この取得は変換結果のキャッシュとは別経路なので、
 * actions/cache が当たっていても飛ぶ）。65 点ぶんのラウンドトリップが毎回入り、
 * ビルドの所要時間だけでなく成否まで外部サービスに繋がってしまう。
 *
 * 縦横は撮影時に分かっていて `docs/tutorial/images/manifest.json` に入っている。
 * それを本文の image ノードへ渡してやれば `inferSize` は立たず、取得も起きない
 * （@astrojs/markdown-remark の rehype-images は width / height があれば
 * `inferSize` を付けない）。ついでにレイアウトシフトの防止にもなる。
 *
 * 台帳に無い URL は素通しする（何も壊さず、従来どおり Astro に任せる）。
 */
const MANIFEST = new URL('../../../docs/tutorial/images/manifest.json', import.meta.url);

function loadSizes() {
  const sizes = new Map();
  let shots;
  try {
    shots = JSON.parse(readFileSync(fileURLToPath(MANIFEST), 'utf8')).shots ?? {};
  } catch {
    // 台帳が読めなくても本文は出せるべき（寸法が付かないだけ）。
    return sizes;
  }
  for (const entry of Object.values(shots)) {
    if (entry.url && entry.width && entry.height) {
      sizes.set(entry.url, { width: entry.width, height: entry.height });
    }
    const motion = entry.motion;
    if (motion?.url && motion.outputWidth && motion.outputHeight) {
      sizes.set(motion.url, { width: motion.outputWidth, height: motion.outputHeight });
    }
  }
  return sizes;
}

export function remarkTutorialImageSize() {
  const sizes = loadSizes();
  return (tree) => {
    if (sizes.size === 0) return;
    visit(tree, 'image', (node) => {
      const size = sizes.get(node.url);
      if (!size) return;
      // hProperties は mdast → hast の変換時にそのまま属性になる。
      node.data ??= {};
      node.data.hProperties = { ...node.data.hProperties, ...size };
    });
  };
}

export default remarkTutorialImageSize;
