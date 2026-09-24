---
title: "転送量が減ったことを速さの証拠にしない——old/new を建てて Lighthouse 30 走、LCP −454〜−1,347 ms"
emoji: "⏱️"
type: "tech"
topics: ["lighthouse", "webperformance", "astro", "webfont", "計測"]
published: true
---


フォントの subset を直し、画像を WebP にして、`<img>` に寸法を付けた。転送量は確かに減った。では LCP は何秒動いたのか——「軽くした」と「速くなった」を別の列で検収するために、直す前後の commit を同じ PC の worktree に建てて Lighthouse を 30 走させました。

## 先に結論

1. 模擬 LCP の中央値は **トップ 3,610→3,010・Lab 記事 4,806→3,459・料金 3,313→2,859 ms**（−600／−1,347／−454）。5 回の四分位範囲は ≤145 ms で、差は幅の外＝識別できた。転送量は 425→344・678→421・395→314 KiB。
2. **CLS は old も new も 0.000〜0.001。**「`width`/`height` を付けたら CLS が下がる」は、この方法では見えない（図は初期表示の外）。
3. 言えるのは「この変更セットの前後で、同一ローカル条件の模擬 LCP が下がった」まで。WebP で何秒・フォントで何秒は分けていない。走行時の CPU 目安（benchmarkIndex）は 3 頁とも new 側が高く、new に有利な偏りが残る。

## 手順

- **仮説を先に固定**: H1 トップの LCP が下がる／H2 Lab 記事の CLS が下がる（寸法を付けた）／H3 料金頁の LCP が下がる。停止条件＝差 < 5 回の四分位範囲なら HOLD。
- **old を建てる**: `git worktree add ../site-old 88b702d` → `astro build` → `astro preview --port 4321`。new＝`1ba941a`（HEAD）の dist を :4322。
- **走る**: `npx lighthouse@13.5.0 <url> --preset=perf --form-factor=mobile --throttling-method=simulate --output=json`。3 頁 × 5 回・old/new を交互（時間のドリフトを片側に寄せない）。`benchmarkIndex` も残す。
- **数える**: LCP・FCP・CLS・転送量（`network-requests` の合計・フォント・画像）・LCP 要素と内訳（`lcp-breakdown-insight`）。中央値と四分位範囲。

```js
// t33_run.mjs（抜粋）: 頁ごとに old/new を交互に 10 走（時間ドリフトを片側に寄せない）
const SERVERS = { old: 'http://localhost:4321', new: 'http://localhost:4322' };
const ORDER = ['old', 'new', 'new', 'old', 'old', 'new', 'new', 'old', 'old', 'new'];
// Windows: chrome-launcher の一時フォルダ削除で EPERM が出て exit 1 になるが JSON は書かれている＝例外を握らず、ファイルの有無で判定する
```

## 数値

転送量はバイト ÷ 1,024 の KiB（Lighthouse の表示に合わせた）。

| 頁 | 転送量 old→new（KiB） | うちフォント | うち画像 | LCP 中央値 | 5 回の最小〜最大（old／new） | 差 | CLS |
|---|---|---|---|---|---|---|---|
| `/` | 425→344 | 388→305 | 1→1 | **3,610→3,010 ms** | 3,460–3,610／3,008–3,012 | **−600** | 0→0 |
| `/lab/green-is-not-proof/` | 678→421 | 359→275 | 276→101（WebP） | **4,806→3,459 ms** | 4,805–4,807／3,309–3,461 | **−1,347** | 0→0 |
| `/works/pricing/` | 395→314 | 359→275 | 1→1 | **3,313→2,859 ms** | 3,309–3,616／2,859–2,860 | **−454** | 0.001→0.001 |

![検収表: 3 頁 × old／new の転送量差と LCP 差を別の列に。トップ −81 KiB／−600 ms・Lab −257 KiB／−1,347 ms・料金 −81 KiB／−454 ms・CLS はどれも変わらず](/images/transfer-size-vs-lcp-old-new/fig1_kb_vs_lcp.png)

- FCP 中央値: 3,010→2,260／2,708→1,959／2,709→1,959 ms。TBT 0。
- 四分位範囲（昇順の 2 番目と 4 番目の差）: old 0〜145 ms・new 1 ms（simulate はほぼ決定的）。停止基準に使ったのはこの四分位範囲で、表の「最小〜最大」ではありません。
- benchmarkIndex（ホスト CPU の目安）: 頁別の中央値 old→new＝`/` 2,985→3,246・Lab 3,239→3,304・料金 2,193→2,242。**3 頁とも new 側が高い。** Lighthouse の CPU 減速はホスト性能に相対なので、観測した差の全量を変更セットの効果とは断定しない。ただし old の 5 走の中では、benchmarkIndex が 2,417〜3,329 と約 900 動いても LCP は 3,460〜3,610 の 150 の幅に収まっている（観測・断定ではない）。
- LCP 要素: 3 頁とも文字（h1・`p.sub`）。内訳は TTFB 5〜6 ms・render delay 183〜258 ms＝render delay 側に寄っている（何を待っていたかは、この内訳だけでは言えない）。

## うまくいかなかったこと

- 初回の走行は chrome-launcher の一時フォルダ削除で `EPERM` が出て exit 1 になった（JSON は書けていた）。器を「例外でなくファイルの有無で判定」に直して再走。
- Lighthouse 13 の perf preset では `largest-contentful-paint-element` が無く `lcp-breakdown-insight` に変わっていた。
- **凍結した new と実走の new がずれた**: 設計で凍結した commit の 4 つ後（Lab 4 本の追加）で走らせていた。差分を見ると比較 3 頁の HTML・CSS・レイアウトは同じで、フォントの woff2 が太字 10 字の追加で計 +2.6 KiB（転送量の 1% 未満）。再走はせず、この 1 行を残す。
- H2 は外れた。old も CLS 0.000。

## 検証の記録

- H1（トップの LCP）→ 支持（−600 ms・幅の外）。H3（料金頁）→ 支持（−454 ms）。H2（CLS）→ 外れ。
- PASS の意味＝事前の停止基準の上で差を観測できた、まで。変更で速くなったことを厳密に証明した PASS ではない（CPU 条件が new 有利・因果は分けていない）。
- 測っていない: 本番の CWV（Web Analytics・Search Console・CrUX が十分な期間貯まってから別記事）。simulate は実測トレースから別条件を推定する方式で、実環境とは別物。

## 持ち帰り: 3 列の検収表

| 列 | 例（今回） | 判定の仕方 |
|---|---|---|
| 代理指標 | 転送量 −81〜−257 KiB | 減ったか（減っていても成果の証拠ではない） |
| 成果指標 | 模擬 LCP −454〜−1,347 ms／CLS 0→0 | 差が再現の幅（5 回の四分位範囲）の外か |
| 停止条件 | 差 < 四分位範囲なら HOLD | 走る前に書く |

「KiB が減った」と「LCP が下がった」は別の列に置いて、両方を検収する。old／new を同じ機械に建てて交互に 5 回ずつ走らせるだけで、1 回の値の幅（以前の記録では 1.2 s）に埋もれない比較になります。

### AI の利用について

走らせる器・集計・この記事の下書きには AI（Claude Code）を使っています。仮説 3 つは走る前に固定し、判定は器の出力（JSON 30 本）から写しました。何が効いたかの因果は言わないと決めたのは人です。案件の情報は含みません。

### 関連

- 本家（検証の記録・30 走の要点 CSV・器）: https://sumitsuke.jp/via/zenn/lab/transfer-size-vs-lcp-old-new/
- 前後の中身＝subset の版と太字の漏れ: https://sumitsuke.jp/via/zenn/lab/font-subset-cache-version-mix/
- 前後の中身＝WebP と寸法: https://sumitsuke.jp/via/zenn/lab/site-metadata-five-gaps-generators/
- 同じ型の 2 本＝「代理指標と成果を分けて検収する」: [AI に「20〜30% 短くして」と頼むと中央値 −7〜−8%](https://sumitsuke.jp/via/zenn/lab/ask-ai-to-cut-30-percent-stops-at-8/)／[画像レビューは閾値をどこまで測れるか](https://sumitsuke.jp/via/zenn/lab/screenshot-ai-vs-dom-ten-rules/)

---

Sumitsuke は、AI や外注で作ったものの点検と修理、業務自動化、検証を受託しています。「軽くしたはずなのに速くならない」の切り分けは → https://sumitsuke.jp/via/zenn/works/repair/
