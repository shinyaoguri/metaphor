import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { visit } from 'unist-util-visit';

/**
 * チュートリアル本文の Gyazo 画像を、台帳 `docs/tutorial/images/manifest.json` を
 * 正として整える。やることは 2 つ。
 *
 * **1. 縦横を焼き込む。** 画像の実体は Gyazo にあり、本文は絶対 URL で指している
 * （ADR-0010）。Astro はリモート画像の縦横が分からないと `inferSize` を立て、
 * **ビルドのたびに画像ごと 1 回ずつ寸法を取りに行く**（この取得は変換結果の
 * キャッシュとは別経路なので、actions/cache が当たっていても飛ぶ）。65 点ぶんの
 * ラウンドトリップが毎回入り、ビルドの所要時間だけでなく成否まで外部サービスに
 * 繋がってしまう。縦横は撮影時に分かっていて台帳に入っているので、それを本文の
 * image ノードへ渡してやれば `inferSize` は立たず、取得も起きない
 * （@astrojs/markdown-remark の rehype-images は width / height があれば
 * `inferSize` を付けない）。ついでにレイアウトシフトの防止にもなる。
 *
 * **2. 動きの証跡に印を付ける。** 動きのある節は「代表静止画 → アニメーション
 * WebP」の 2 行が並ぶ（README の「動きの証跡」）。どちらも拡張子は `.webp` に
 * 変換されて出るので、出力からは区別が付かない。台帳は静止画（`url`）と動き
 * （`motion.url`）を同じエントリに持っているので、ここでしか付けられない印を
 * 付けておく。`prefers-reduced-motion: reduce` の読者には動くほうを出さない
 * （global.css）— 対の静止画がすぐ上に残るので、絵は失われない（#553）。
 *
 * 台帳に無い URL は素通しする（何も壊さず、従来どおり Astro に任せる）。
 */
const MANIFEST = new URL('../../../docs/tutorial/images/manifest.json', import.meta.url);

/** 動きの証跡を包む段落に付く印。global.css がこれを見て出し分ける。 */
export const MOTION_CLASS = 'tutorial-motion';

function loadManifest() {
  const sizes = new Map();
  const motionUrls = new Set();
  let shots;
  try {
    shots = JSON.parse(readFileSync(fileURLToPath(MANIFEST), 'utf8')).shots ?? {};
  } catch {
    // 台帳が読めなくても本文は出せるべき（寸法と印が付かないだけ）。
    return { sizes, motionUrls };
  }
  for (const entry of Object.values(shots)) {
    if (entry.url && entry.width && entry.height) {
      sizes.set(entry.url, { width: entry.width, height: entry.height });
    }
    const motion = entry.motion;
    if (!motion?.url) continue;
    motionUrls.add(motion.url);
    if (motion.outputWidth && motion.outputHeight) {
      sizes.set(motion.url, { width: motion.outputWidth, height: motion.outputHeight });
    }
  }
  return { sizes, motionUrls };
}

function addClass(node, className) {
  node.data ??= {};
  const properties = (node.data.hProperties ??= {});
  const existing = properties.className;
  const classes = Array.isArray(existing) ? existing : existing ? [existing] : [];
  if (!classes.includes(className)) classes.push(className);
  properties.className = classes;
}

export function remarkTutorialImages() {
  const { sizes, motionUrls } = loadManifest();
  return (tree) => {
    if (sizes.size === 0 && motionUrls.size === 0) return;
    visit(tree, 'image', (node, index, parent) => {
      const size = sizes.get(node.url);
      if (size) {
        // hProperties は mdast → hast の変換時にそのまま属性になる。
        node.data ??= {};
        node.data.hProperties = { ...node.data.hProperties, ...size };
      }
      if (!motionUrls.has(node.url)) return;
      addClass(node, MOTION_CLASS);
      // 画像行は独立した 1 行と決めているので（README の執筆規約）、段落ごと
      // 出し分けられる。余白ごと消さないと、隠したときに空の段落が残る。
      if (parent?.type === 'paragraph' && parent.children.length === 1) {
        addClass(parent, MOTION_CLASS);
      }
    });
  };
}

export default remarkTutorialImages;
