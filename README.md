# metaphor

[![Release](https://img.shields.io/github/v/release/shinyaoguri/metaphor?label=version)](https://github.com/shinyaoguri/metaphor/releases/latest)
[![CI](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml/badge.svg)](https://github.com/shinyaoguri/metaphor/actions/workflows/ci.yml)
[![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://developer.apple.com/macos/)
[![License MIT](https://img.shields.io/github/license/shinyaoguri/metaphor)](LICENSE)

Processingにインスパイアされた、Swift + Metal クリエイティブコーディングライブラリ。

## 動作環境

- macOS 14.0+
- Xcode 15.0+
- Swift 5.10+

---

## インストール

### Swift Package Manager

`Package.swift` に metaphor を追加してください:

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.1"),
]
```

Xcode の場合: File → Add Package Dependencies → リポジトリ URL を入力。

---

## クイックスタート

```bash
mkdir MyMetalApp && cd MyMetalApp
swift package init --type executable --name MyMetalApp
```

`Package.swift` を編集:

```swift
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MyMetalApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "MyMetalApp",
            dependencies: [
                .product(name: "metaphor", package: "metaphor")
            ]
        ),
    ]
)
```

ビルドして実行:

```bash
swift build && swift run
```

---


---


### セットアップ

サブモジュールごとクローンし、Syphon をローカルビルドします:

```bash
git clone --recursive https://github.com/shinyaoguri/metaphor.git
cd metaphor
make setup
```

### 開発コマンド

```bash
make setup      # サブモジュール初期化 + Syphon.xcframework ビルド
make build      # ライブラリをビルド
make test       # テスト実行（10ターゲット、約900テスト）
make clean      # ビルド成果物をクリーン
make check      # セットアップ状態を確認
make docs       # DocC ドキュメントをビルド
```

### Syphon の仕組み

- **ローカル開発**: `Frameworks/Syphon.xcframework` が存在する場合、Package.swift はローカルパスを使用します。
- **SPM ユーザー**: フレームワークが存在しない場合、Package.swift が GitHub Releases からビルド済み XCFramework を取得します。

### リリースプロセス

1. 新しいバージョンをタグ付け:
   ```bash
   git tag v0.X.X
   git push --tags
   ```

2. GitHub Actions が自動的に以下を実行:
   - Syphon.xcframework をビルド
   - XCFramework を含む GitHub Release を作成
   - Package.swift の URL とチェックサムを更新
   - 変更を main にコミット

---

## 謝辞

[Examples/](Examples/) ディレクトリの多くのサンプルは、
Casey Reas、Ben Fry、Daniel Shiffman による
[Processing](https://processing.org/) サンプルスケッチ（public domain）の Swift/Metal 移植です。
個別の帰属情報は各ファイルのヘッダーコメントを参照してください。

- Processing: https://processing.org/
- Processing examples: https://github.com/processing/processing-examples

---
