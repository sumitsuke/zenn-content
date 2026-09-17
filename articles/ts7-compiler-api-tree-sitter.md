---
title: "TypeScript 7.0 で従来の Compiler API が使えなかった——tree-sitter に切り替えた記録"
emoji: "🧭"
type: "tech"
topics: ["TypeScript", "treesitter", "Node", "静的解析", "移行"]
published: false
---

<!-- 図: 図/t1_exports.png（第 6 陣・overflow 0） -->

TypeScript 7.0 に上げたあと、`typescript` パッケージの API で書いていた解析スクリプトが動かなくなりました。**原因の半分は当方の入れ方の誤り、残り半分は 7.0 の仕様**でした。両方を切り分けて、解析を tree-sitter に切り替えた結果まで書きます。

結果を先に書きます（2026-09-17 時点・`typescript@7.0.2`・Node v24.14.0・Windows 11）。

- ローカルの `node_modules` から `require("typescript")` すると、返るのは **`version` と `versionMajorMinor` の 2 キーだけ**です。`ts.createSourceFile` はありません
- 公式の 7.0 発表（2026-07-08）は「7.0 は API を同梱しない。7.1 で新しい API を出す見込み」としています。移行策として **`@typescript/typescript6`**（6.0 の API を再エクスポート）が用意されています
- 一方で、7.0.2 のパッケージには **`typescript/unstable/sync`・`typescript/unstable/ast`（409 個のエクスポート）が入っています**。「AST の API が無い」は誤りで、正しくは「安定した API が無い」です。ただし `unstable/ast` は**ノード型・走査・scanner の部品集**で、ソース文字列から AST を作る関数（6 系の `createSourceFile` 相当）はありません
- 当方の用途（60 本の TypeScript から「既定値を返す場所」の形だけ取る）は tree-sitter に切り替えました。**既存の正規表現による分類と 60 本中 58 本で一致**しました。これは正解率ではなく、旧分類との一致率です。ずれた 2 本は両方とも「コメントだけの catch」で、そこに意味論の境界がありました

最初に `MODULE_NOT_FOUND` が出たのは、7.0 のせいではありません。**グローバルに入れたパッケージを `require()` していた**からです。ここを証拠にしかけたので、先に書いておきます。

![typescript@7.0.2 の exports: ルートは lib/version.cjs（version と versionMajorMinor の 2 キー）、AST と API は unstable の下（unstable/ast は 409 エクスポート）。解析用途の道は 3 つ＝@typescript/typescript6・unstable/ast・tree-sitter（既存分類と 60 本中 58 本一致）。グローバル導入での MODULE_NOT_FOUND は API 欠如の証拠にならない](/images/ts7-compiler-api-tree-sitter/t1_exports.png)

## 何が起きたか（時系列）

当時のコマンドの逐語は残っていないので、順 1〜3 は作業記録からの再構成です。順 4・5 はこの記事を書く際に叩き直した出力です。

| 順 | やったこと | 見えたもの |
|---|---|---|
| 1 | グローバルに 7.0.2 を入れた状態で `node -e "require('typescript')"` | `MODULE_NOT_FOUND` |
| 2 | グローバルの `lib/` を見る | `tsc.js`・`version.cjs`・`getExePath.js`（と型定義）だけ。`typescript.js` が無い |
| 3 | 「API が消えた」と判断して tree-sitter で書き直す | 60 本の形の列が埋まる（下記） |
| 4 | 後日、証拠を疑って `node_modules` に置き直して `require` | **落ちない**。返るのは version の 2 キー |
| 5 | `package.json` の `exports` を読む | `"."` は `./lib/version.cjs`。`./unstable/*` が 11 本 |

順 1 の失敗は Node の解決規則どおりです。`require()` はカレントから上へ `node_modules` を探すだけで、npm のグローバル領域は見ません。**順 3 の判断は、結論はほぼ合っていて、根拠が間違っていました。**

## 7.0.2 のパッケージに何が入っているか

`package.json` の `exports` をそのまま載せます。

```json
{
 "./package.json": "./package.json",
 ".": "./lib/version.cjs",
 "./unstable/sync": "./dist/api/sync/api.js",
 "./unstable/async": "./dist/api/async/api.js",
 "./unstable/fs": "./dist/api/fs.js",
 "./unstable/proto": "./dist/api/proto.js",
 "./unstable/ast": "./dist/ast/index.js",
 "./unstable/ast/is": "./dist/ast/is.js",
 "./unstable/ast/factory": "./dist/ast/factory.generated.js",
 "./unstable/ast/utils": "./dist/ast/utils.js",
 "./unstable/ast/scanner": "./dist/ast/scanner.js",
 "./unstable/ast/visitor": "./dist/ast/visitor.js",
 "./unstable/ast/clone": "./dist/ast/clone.js"
}
```

ローカルの `node_modules` から叩いた出力です（抜粋）。

```
require("typescript")               keys = [ 'version', 'versionMajorMinor' ]
require("typescript/unstable/sync") keys = [ 'API', 'Checker', 'CompletionItemKind', 'DiagnosticCategory', ... ]
require("typescript/unstable/ast")  keys = 409 個
```

つまり、**ルートの export は version だけ**、**API と AST の部品は `unstable` の下に在る**、という状態です。ESM の `import` でも同じでした。

`unstable/ast` の 409 個のうち、名前に parse／SourceFile／create を含むのは `createScanner`・`isSourceFile`・`cloneSourceFileData` の 3 つだけで、**ソース文字列を受け取って AST を返す関数はありません**。`unstable/sync` の `API` クラスは `parseConfigFile`・`updateSnapshot` を持ち、Project／Snapshot 経由で扱う形です。当方が欲しかった「1 ファイルの文字列 → AST」の単体パーサは、7.0.2 の unstable には無い、というのが現物の観測です。

公式発表の該当箇所は次の 1 文です。7.0 が Go で書き直された版（"a native port of TypeScript built in Go"）であることも同じ発表に書かれています。

> "While TypeScript 7.0 is here, it does not ship with an API. We expect TypeScript 7.1 to ship with a new (and different) API, but until then we have made it a priority to ensure TypeScript can be run side-by-side with TypeScript 6.0 for utilities that still need some programmatic access to the compiler"
> （Announcing TypeScript 7.0・2026-07-08）

"We expect" なので、7.1 の API は**見込み**です。確約とは読みません。

同じ記事が `@typescript/typescript6` を案内しています。`tsc6` という実行ファイルを持ち、6.0 の API を再エクスポートするパッケージです。`typescript@7` と名前が衝突せずに同居できます。

## 今回検討した 3 経路

| 経路 | 何が得られるか | 当方が選ばなかった／選んだ理由 |
|---|---|---|
| 互換 API を使う＝`@typescript/typescript6` | 6.0 の Compiler API そのまま | 既存コードを温存するなら第一候補。当方は温存するコードが無かった |
| 7 系の実験的 AST 部品＝`typescript/unstable/ast` | ノード型・走査・scanner | ソース文字列から AST を作る関数が無く、API は Project／Snapshot 経由。**今回欲しい単体パーサではない**。名前どおり保証もない |
| 別パーサを使う＝tree-sitter | 構文の形だけ。型は無い | **取りたいのは「return の形」だけ**だったので、これで足りた |

「2 択」ではありません。当時の当方は 3 つ目しか見えていませんでした。世の中の選択肢がこの 3 つだけだとも言いません。

## tree-sitter で作った列と、既存分類との一致

用途は、AI が生成した TypeScript 60 本について「try/catch の外で既定値（`null`・`undefined`・`[]`・`{}`・`false`・空文字）を返しているか」「catch の中で返しているか」を列にすることです。Python 側は標準の `ast` で同じ列を作ってあり、TypeScript だけ空でした。

pip で `tree-sitter 0.26.0`・`tree-sitter-typescript 0.23.2` を入れ、`return_statement` を歩いて既定値かどうかを見るだけの 60 行ほどを足しました。記事の数字を出した正規表現の判定は列に残し、tree-sitter の判定と**食い違う行を印字**する形にしています。

再実行した結果です。

```
TS rows where the tree-sitter handling differs from the regex handling kept in `handling`:
[('ts_load_config_s0', 'proper', 'swallow_cand'), ('ts_load_config_s2', 'proper', 'swallow_cand')]
```

60 本中 58 本が一致し、2 本がずれました。**一致率は「旧分類とどれだけ同じ答えを出したか」で、正解率ではありません**。旧分類が間違っていれば、一致しても間違いです。

面白いのはずれた 2 本のほうです。2 本の中身は同じ形です。関数本体は「ログを出して投げ直す」ので正規表現は `proper` と判定します。ところが、ファイル末尾のデモ用ブロックに **コメントだけの `catch {}`** があり、tree-sitter は「文が無い catch」として `swallow_cand`（握り潰し候補）に振りました。

この 2 本は、同じコーパスを Semgrep の素朴なルールで走らせたときにも偽陽性として挙がった行です。**tree-sitter は Semgrep と同じ偽陽性を再現した**、と言えます。パーサを変えても「コメントだけの catch は空の catch か」という問いは消えません。構文の上では空で、意図の上では「ここでは何もしない」と書いてあります。**この境界は構文解析では決まらず、規則を書く人が決めるものです**。当方は 2 本とも「関数本体は proper。末尾のデモ用ブロックのコメントだけの catch は関数の判定に数えない（偽陽性）」と裁定し、`gt.csv` の `review_note` にそう書いてあります。tree-sitter の列はその裁定を変えていません。

## 移行前に叩く 2 行

当方が最初にやるべきだった確認です。ローカルに入れた状態で叩きます。

```bash
node -p "Object.keys(require('typescript'))"
node -p "require('typescript/package.json').exports"
```

1 行目が `['version', 'versionMajorMinor']` なら、ルートに API はありません。2 行目で `unstable` の有無と、何が export されているかが分かります。**グローバル導入で `require` して落ちたら、それは何の証拠にもなりません。**

## この 1 本から言えること／言えないこと

言えること（当方の環境で観測したこと）:

- `typescript@7.0.2` のルート export は version の 2 キーだけです
- `typescript/unstable/sync`・`typescript/unstable/ast` は 7.0.2 に入っています
- 公式は 7.0 に安定 API を同梱していないと書き、`@typescript/typescript6` を移行策として案内しています。7.1 の API は見込みです
- tree-sitter で作った形の列は、既存の正規表現分類と 60 本中 58 本で一致しました。ずれた 2 本はコメントだけの catch でした

言えないこと:

- 「TypeScript 7 には AST の API が無い」とは言いません。unstable が在ります。ただし「unstable/ast で文字列を解析できる」とも言いません。7.0.2 には単体パーサの関数がありませんでした
- 「TypeScript 7 は壊れている」とも言いません。`tsc` は動きます
- 「tree-sitter が正解」とも言いません。58/60 は旧分類との一致率で、2 本ずれましたし、型情報は取れません
- `unstable/*` の中身の質は評価していません。在ること・エクスポート名・単体パーサの関数が無いことを確認しただけです
- 7.1 以降で何が変わるかは書けません。この記事は **7.0.2・2026-09-17 時点**の観測です

## 再現したい人へ

1. `mkdir probe && cd probe && npm i typescript@7.0.2`（グローバルではなくローカルに）
2. 上の 2 行を叩く
3. tree-sitter 側は `pip install tree-sitter==0.26.0 tree-sitter-typescript==0.23.2`。コードとコーパスは公開リポ `ai-silent-defect-scanner` の `scripts/build_gt.py`（commit `f839873`）にあります。`python scripts/build_gt.py` で上の「differs」の 2 行が印字されます

### AI の利用について

パッケージの中身の確認・tree-sitter のコード・この記事の下書きは AI（Claude Code）が行い、公式発表の確認と公開の判断は人が行っています。数字は全部、コマンドの出力から写しています。

### 関連

この記事は「固定する → 測る → 道具を選ぶ → 公開後に伝播する」の 4 本のうち、**道具を選ぶ**の回です。持ち帰りは上の 2 行と「3 経路」の表です。

- 3 経路の比較は当方の用途（return の形だけ）での話です

- 60 本のコーパスを作った元の記事: [AI が書いたコードは失敗を握り潰すか——120 本を測った](https://sumitsuke.jp/via/zenn/lab/ai-code-silent-fallback/)
- 器を信じる前に毒を 1 本入れる話: [緑を信じない——捕まえた 5 件・直した 22 件](https://sumitsuke.jp/via/zenn/lab/green-is-not-proof/)
