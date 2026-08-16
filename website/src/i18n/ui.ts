// Bilingual content for the metaphor landing page.
// Components receive `lang` and read the matching entry from `content`.

export const languages = ['ja', 'en'] as const;
export type Lang = (typeof languages)[number];
export const defaultLang: Lang = 'ja';

/** Normalized base path without trailing slash, e.g. "/metaphor". */
export const base = import.meta.env.BASE_URL.replace(/\/$/, '');

/** Home URL for a locale. ja lives at the root, en at /en/. */
export function homeFor(lang: Lang): string {
  return lang === 'en' ? `${base}/en/` : `${base}/`;
}

/** The "other" locale, for the language toggle. */
export function otherLang(lang: Lang): Lang {
  return lang === 'en' ? 'ja' : 'en';
}

/**
 * API リファレンス（DocC）の入口。DocC は Astro とは別にビルドされ、
 * `/reference/` 配下へ丸ごと置かれる（`.github/workflows/docs.yml`）。
 *
 * `/reference/` 自体は DocC の出力ルートで、開くと SPA が "page can't be found"
 * を出す（リダイレクタではない）。リンク先は必ずフレームワークのページまで指すこと。
 *
 * 導線の呼称は「リファレンス / Reference」。チュートリアルもドキュメントなので
 * 「ドキュメント」では並列の選択肢にならず、指しているのは型やメソッドを引く場所
 * だから（#530。README と p5.js の Reference もこの語）。
 *
 * 日本語版は `/reference/ja/` に同じ構造で並ぶ（ADR-0011）。英語の doc コメントが
 * 正典で、日本語は台帳を当てた生成物。読者を入口で取り違えないよう、サイトの言語
 * に合わせて入口を出し分ける（リファレンス内での切り替えは DocC 側のヘッダーが担う）。
 */
export function referenceUrlFor(lang: Lang): string {
  return lang === 'ja'
    ? `${base}/reference/ja/documentation/metaphor/`
    : `${base}/reference/documentation/metaphor/`;
}
export const githubUrl = 'https://github.com/shinyaoguri/metaphor';
export const examplesUrl = 'https://github.com/shinyaoguri/metaphor/tree/main/Examples';
/** チュートリアル本文の正典（website はここを content collection として読む）。 */
export const tutorialSourceUrl =
  'https://github.com/shinyaoguri/metaphor/tree/main/docs/tutorial';

interface Content {
  meta: { title: string; description: string };
  nav: { reference: string; tutorial: string; toggleLabel: string };
  tutorial: {
    /** 一覧ページの <title> と description。 */
    meta: { title: string; description: string };
    eyebrow: string;
    title: string;
    lead: string;
    /** サイドバー / パンくずに出る「チュートリアル」。 */
    home: string;
    /** サイドバーの章立て見出し。 */
    contents: string;
    /** 節内目次の見出し。 */
    onThisPage: string;
    prev: string;
    next: string;
    /** `{n}` を部番号に置換して使う。 */
    partLabel: string;
    /** 本文が 1 本も無いときの案内。 */
    empty: { title: string; body: string; cta: string };
    /** 訳が無い部を既定言語の本文で出すときの告知。 */
    pending: { title: string; body: string };
    editOnGitHub: string;
  };
  hero: {
    badge: string;
    titleLead: string;
    titleAccent: string;
    lead: string;
    ctaReference: string;
    ctaGithub: string;
    swiftLabel: string;
    brewLabel: string;
    envNote: string;
  };
  ai: {
    eyebrow: string;
    title: string;
    lead: string;
    cards: { icon: string; title: string; desc: string }[];
    toolsLabel: string;
    tools: { name: string; desc: string }[];
  };
  features: {
    title: string;
    subtitle: string;
    items: { icon: string; title: string; desc: string }[];
  };
  code: {
    title: string;
    titleAccent: string;
    lead: string;
    points: string[];
  };
  cli: {
    title: string;
    lead: string;
    steps: { cmd: string; desc: string }[];
  };
  examples: {
    title: string;
    subtitle: string;
    categories: { title: string; desc: string; items: string[] }[];
    cta: string;
  };
  footer: { license: string; reference: string };
}

export const content: Record<Lang, Content> = {
  ja: {
    meta: {
      title: 'metaphor — Swift + Metal のクリエイティブコーディング',
      description:
        '思いついた絵を、そのままコードに。2D・3D、GPU、音、映像までを draw() だけのシンプルな API でスケッチできる macOS ネイティブのクリエイティブコーディング・ランタイム。AI と観測ループを回せるのも大きな特長です。',
    },
    nav: { reference: 'リファレンス', tutorial: 'チュートリアル', toggleLabel: 'EN' },
    tutorial: {
      meta: {
        title: 'チュートリアル — metaphor',
        description:
          'Processing 経験を前提としない、metaphor の体系的なチュートリアルです。最初のスケッチから 2D・3D・GPU・メディア、そして AI と作るところまでを順に読み進められます。',
      },
      eyebrow: '順に読む',
      title: 'チュートリアル',
      lead: '最初から順に読んで、作品を作れるようになるための読み物です。各節に完結したコードと実行結果が付きます。型やメソッドの詳細を引きたいときは API リファレンスへ。',
      home: 'チュートリアル',
      contents: '章立て',
      onThisPage: 'このページの内容',
      prev: '前の部',
      next: '次の部',
      partLabel: '第 {n} 部',
      empty: {
        title: '本文を準備しています',
        body: 'チュートリアルの章立ては確定していて、本文は部ごとに順次追加されます。いまの章立てと執筆規約は GitHub で読めます。',
        cta: '章立てを GitHub で見る',
      },
      pending: {
        title: '英訳は準備中です',
        body: 'この部はまだ英訳がないため、日本語の本文を表示しています。',
      },
      editOnGitHub: 'GitHub でこのページを編集する',
    },
    hero: {
      badge: 'オープンソース · Swift + Metal',
      titleLead: 'Metal で描く、',
      titleAccent: 'クリエイティブコーディング',
      lead: '思いついた絵を、そのままコードに。2D・3D、GPU コンピュート、音、映像までを、Processing 譲りの draw() だけのシンプルな API でスケッチできます。そして metaphor の最大の魅力は、AI が「いま動いている作品」を見ながら、あなたと一緒に手を入れられることです。',
      ctaReference: 'リファレンスを見る',
      ctaGithub: 'GitHub',
      swiftLabel: 'SwiftPM',
      brewLabel: 'CLI',
      envNote: 'macOS 14+ · Apple Silicon · Swift 5.10+',
    },
    ai: {
      eyebrow: 'metaphor ならでは · 観測ループ',
      title: 'コードを書くだけでなく、絵を見ながら直す',
      lead: 'これが metaphor のいちばんの推しです。一般的な AI はソースコードしか見られませんが、metaphor は「実行中の画像」と「内部状態」をエージェントに渡し、作りながら観測して反復するループを成立させます。',
      cards: [
        {
          icon: '◉',
          title: 'のぞき窓（Probe）',
          desc: 'draw() 内で probe("particles.count", n) と申告するだけ。現在フレーム画像と内部状態が JSON に記録され、AI が観測できます。',
        },
        {
          icon: '◐',
          title: 'ライブビューア',
          desc: 'metaphor watch でコードを保存するたび即座に再描画。人間も AI と同じ実行中の作品を同時に見られます。',
        },
        {
          icon: '⌘',
          title: 'ローカル MCP',
          desc: 'metaphor mcp で MCP サーバを起動。Claude などが実行中の絵を観測しながらコードを反復します。',
        },
      ],
      toolsLabel: 'MCP ツール',
      tools: [
        { name: 'snapshot', desc: '現在フレーム画像 + 内部状態を返す' },
        { name: 'capture_sequence', desc: '連続フレーム列をコンタクトシートで取得' },
        { name: 'input', desc: '実行中スケッチへマウス・キー入力を注入' },
        { name: 'build_status', desc: '直近ビルドの成否・エラーを取得' },
        { name: 'api_reference', desc: 'API・作法・サンプル索引を提供' },
      ],
    },
    features: {
      title: 'スケッチから、作品の完成まで',
      subtitle:
        '2D の一筆から GPU コンピュートまで。Metal の上に、作品づくりに必要な道具がひと続きで揃っています。',
      items: [
        { icon: '◆', title: '2D 描画', desc: 'シェイプ・テキスト・画像・グラデーション・ブレンドモードのイミディエイトモード描画。GPU インスタンシングで高速。' },
        { icon: '◇', title: '3D・ライティング', desc: 'PBR / Blinn-Phong、シャドウマッピング、OBJ/USDZ 読み込み、ディレクショナル/ポイント/スポットライト、オービットカメラ。' },
        { icon: '⚡', title: 'GPU コンピュート', desc: '型付き GPUBuffer<T> によるカスタム Metal カーネル。100 万粒子の GPU パーティクルシステム。' },
        { icon: '✦', title: 'ポストプロセス', desc: 'Bloom・Blur・色収差・カラーグレーディング・フィードバック。PostProcessPipeline で自作エフェクトも。' },
        { icon: '♪', title: 'オーディオ', desc: 'リアルタイム FFT 解析、ビート検出、マイク入力、サウンドファイル再生。' },
        { icon: '⬡', title: '物理・ML', desc: '2D 剛体物理と、CoreML / Vision 統合（分類・検出・セグメント・OCR・顔認識）。' },
        { icon: '❖', title: '合成グラフ', desc: 'RenderGraph の多段オフスクリーン合成と、SceneGraph の階層 3D シーン管理。' },
        { icon: '↗', title: '映像入出力・Syphon', desc: 'カメラ入力、MP4/GIF 書き出し、決定論オフラインレンダリング、Syphon でライブ VJ 出力。' },
      ],
    },
    code: {
      title: '親しみやすい API、',
      titleAccent: 'パワフルなエンジン',
      lead: 'Sketch プロトコルを実装するだけで描画が始まります。ウィンドウ生成・レンダーループ・GPU パイプラインの構築はライブラリが引き受けます。',
      points: [
        'Processing ライクなイミディエイトモード API',
        '自動 GPU インスタンシングとバッチ処理',
        '固定解像度での 2 パスレンダリング',
        'macOS 14+（Apple Silicon）',
      ],
    },
    cli: {
      title: '数コマンドで作りはじめる',
      lead: 'metaphor-cli を入れれば、雛形生成からライブリロード、AI 連携までひと息で。',
      steps: [
        { cmd: 'brew install shinyaoguri/tap/metaphor', desc: 'CLI をインストール' },
        { cmd: 'metaphor new MySketch', desc: '雛形からプロジェクト生成' },
        { cmd: 'metaphor watch', desc: '保存のたびライブリロード表示' },
        { cmd: 'claude mcp add metaphor -- metaphor mcp', desc: 'AI クライアントに MCP を登録' },
      ],
    },
    examples: {
      title: 'サンプルで学ぶ',
      subtitle: '基礎から高度な GPU テクニックまで、286 の実行可能なサンプル（うち 270 が動作確認済み）。',
      categories: [
        { title: 'Basics', desc: 'シェイプ・カラー・数学・入力・タイポグラフィ', items: ['ShapePrimitives', 'Hue', 'Noise2D', 'Interactive'] },
        { title: 'Topics', desc: 'シェーダー・シミュレーション・ジオメトリ・曲線', items: ['Shaders', 'Flocking', 'Fractals', 'Curves'] },
        { title: 'ML', desc: '分類・検出・セグメント・スタイル転送', items: ['ImageClassification', 'FaceDetection', 'PersonSegmentation', 'StyleTransfer'] },
        { title: 'Samples', desc: 'レイトレ・グラフ合成・のぞき窓・Syphon', items: ['RayTracing', 'RenderGraphCompose', 'ProbeSnapshot', 'Syphon'] },
      ],
      cta: 'GitHub で全サンプルを見る',
    },
    footer: { license: 'MIT License', reference: 'リファレンス' },
  },

  en: {
    meta: {
      title: 'metaphor — creative coding for Swift + Metal',
      description:
        'A macOS-native creative coding runtime. Start from a Processing-style draw() and sketch across 2D, 3D, GPU, audio and video in one continuous API — with AI collaboration as a standout feature.',
    },
    nav: { reference: 'Reference', tutorial: 'Tutorial', toggleLabel: '日本語' },
    tutorial: {
      meta: {
        title: 'Tutorial — metaphor',
        description:
          'A guided tour of metaphor that assumes no Processing background: from your first sketch through 2D, 3D, GPU, media, and making things with an AI.',
      },
      eyebrow: 'Read in order',
      title: 'Tutorial',
      lead: 'A read-it-in-order guide that takes you from nothing to finished work. Every section ships a complete sketch and the image it produces. Reach for the API reference when you need a signature.',
      home: 'Tutorial',
      contents: 'Contents',
      onThisPage: 'On this page',
      prev: 'Previous',
      next: 'Next',
      partLabel: 'Part {n}',
      empty: {
        title: 'The chapters are being written',
        body: 'The outline is settled and parts land one by one. The outline and the writing conventions are already readable on GitHub.',
        cta: 'See the outline on GitHub',
      },
      pending: {
        title: 'English translation in progress',
        body: 'This part has not been translated yet, so the Japanese text is shown here.',
      },
      editOnGitHub: 'Edit this page on GitHub',
    },
    hero: {
      badge: 'Open source · Swift + Metal',
      titleLead: 'Creative coding,',
      titleAccent: 'drawn with Metal',
      lead: 'Start from a Processing-style draw() and sketch across 2D, 3D, GPU compute, audio and video — one continuous API. Turn the image in your head straight into code. And an AI can watch the very image on screen and iterate right alongside you: metaphor’s signature move.',
      ctaReference: 'Browse the reference',
      ctaGithub: 'GitHub',
      swiftLabel: 'SwiftPM',
      brewLabel: 'CLI',
      envNote: 'macOS 14+ · Apple Silicon · Swift 5.10+',
    },
    ai: {
      eyebrow: 'Only in metaphor · the observation loop',
      title: 'Not just writing code — fixing it by looking at the image',
      lead: 'This is metaphor’s headline feature. A typical AI only sees source code; metaphor hands the agent the live rendered image and internal state, closing a loop where you observe as you build.',
      cards: [
        {
          icon: '◉',
          title: 'Probe',
          desc: 'Just declare probe("particles.count", n) inside draw(). The current frame image and internal state are recorded to JSON for the AI to observe.',
        },
        {
          icon: '◐',
          title: 'Live viewer',
          desc: 'metaphor watch redraws instantly on every save. Humans see the same running sketch the AI does, at the same time.',
        },
        {
          icon: '⌘',
          title: 'Local MCP',
          desc: 'metaphor mcp starts an MCP server so Claude and others iterate on code while watching the live image.',
        },
      ],
      toolsLabel: 'MCP tools',
      tools: [
        { name: 'snapshot', desc: 'Return the current frame image + internal state' },
        { name: 'capture_sequence', desc: 'Grab a run of frames as a contact sheet' },
        { name: 'input', desc: 'Inject mouse / key input into the running sketch' },
        { name: 'build_status', desc: 'Report the latest build result and errors' },
        { name: 'api_reference', desc: 'Serve API docs, idioms and an example index' },
      ],
    },
    features: {
      title: 'From a sketch to a finished piece',
      subtitle:
        'From a single 2D stroke to a GPU compute pipeline — everything you need to make work, in one toolkit built on Metal.',
      items: [
        { icon: '◆', title: '2D drawing', desc: 'Immediate-mode shapes, text, images, gradients and blend modes. Fast via GPU instancing.' },
        { icon: '◇', title: '3D & lighting', desc: 'PBR / Blinn-Phong, shadow mapping, OBJ/USDZ loading, directional/point/spot lights, orbit camera.' },
        { icon: '⚡', title: 'GPU compute', desc: 'Custom Metal kernels via typed GPUBuffer<T>. A one-million-particle GPU particle system.' },
        { icon: '✦', title: 'Post-processing', desc: 'Bloom, blur, chromatic aberration, color grading and feedback — plus your own via PostProcessPipeline.' },
        { icon: '♪', title: 'Audio', desc: 'Real-time FFT analysis, beat detection, mic input and sound-file playback.' },
        { icon: '⬡', title: 'Physics & ML', desc: '2D rigid-body physics, plus CoreML / Vision (classification, detection, segmentation, OCR, faces).' },
        { icon: '❖', title: 'Compositing graphs', desc: 'Multi-pass offscreen compositing with RenderGraph, hierarchical 3D scenes with SceneGraph.' },
        { icon: '↗', title: 'Video I/O & Syphon', desc: 'Camera input, MP4/GIF export, deterministic offline rendering, and live VJ output over Syphon.' },
      ],
    },
    code: {
      title: 'A friendly API,',
      titleAccent: 'a powerful engine',
      lead: 'Implement the Sketch protocol and drawing begins. Window creation, the render loop and the GPU pipeline are handled for you.',
      points: [
        'Processing-style immediate-mode API',
        'Automatic GPU instancing and batching',
        'Two-pass rendering at a fixed resolution',
        'macOS 14+ (Apple Silicon)',
      ],
    },
    cli: {
      title: 'Start in a few commands',
      lead: 'Install metaphor-cli and go from scaffold to live reload to AI collaboration in one breath.',
      steps: [
        { cmd: 'brew install shinyaoguri/tap/metaphor', desc: 'Install the CLI' },
        { cmd: 'metaphor new MySketch', desc: 'Scaffold a project' },
        { cmd: 'metaphor watch', desc: 'Live-reload on every save' },
        { cmd: 'claude mcp add metaphor -- metaphor mcp', desc: 'Register the MCP server with your AI client' },
      ],
    },
    examples: {
      title: 'Learn from examples',
      subtitle: 'From basics to advanced GPU techniques — 286 runnable examples (270 verified).',
      categories: [
        { title: 'Basics', desc: 'Shapes, color, math, input, typography', items: ['ShapePrimitives', 'Hue', 'Noise2D', 'Interactive'] },
        { title: 'Topics', desc: 'Shaders, simulation, geometry, curves', items: ['Shaders', 'Flocking', 'Fractals', 'Curves'] },
        { title: 'ML', desc: 'Classification, detection, segmentation, style transfer', items: ['ImageClassification', 'FaceDetection', 'PersonSegmentation', 'StyleTransfer'] },
        { title: 'Samples', desc: 'Ray tracing, graph compositing, Probe, Syphon', items: ['RayTracing', 'RenderGraphCompose', 'ProbeSnapshot', 'Syphon'] },
      ],
      cta: 'See all examples on GitHub',
    },
    footer: { license: 'MIT License', reference: 'Reference' },
  },
};

export function getContent(lang: Lang): Content {
  return content[lang];
}
