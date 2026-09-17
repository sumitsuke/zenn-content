---
title: "日本語 Web フォントの太字を見出しの 316 字まで削り、未収録の字でも壊れない形で LCP を縮めた——136→63 KB"
emoji: "🔤"
type: "tech"
topics: ["Webフォント", "パフォーマンス", "Astro", "CSS", "Python"]
published: true
---

自分のサイト（Astro・静的・Cloudflare Pages）で、LCP 要素が h1 だったのに、その h1 が本文フォントの太字（700）の woff2 **136 KB** を待っていました。太字は見出しにしか使わないのに、subset には本文と同じ全字が入っていた。見出しで実際に太字になる字だけを集めて 63 KB の core にし、残りは unicode-range で「必要なときだけ」読む形にしました。数字と、壊れていないことの確かめ方を書きます。

## 先に結論

- 700 の subset は、本文の 400 と同じ字集合を入れていた。太字で実際に描かれる字は **316 字**だった。
- 実測の 316 字と、常駐させる ASCII・かな・CJK 記号の**和集合** 575 字を core（63 KB）、残りを rest（84 KB）に分け、`unicode-range` で core を後に宣言する。core に在る字は core だけを読み、無い字が出たときだけ rest が読まれる。preload は core だけ。
- 転送 386 → 269 KB。Lighthouse（mobile・模擬低速 4G）の LCP は `/works/repair/` で **2.4 → 1.7 s**、トップは 3.2 → 1.8〜3.0 s（3 回で 1.2 s 揺れる）。実機（Cloudflare Web Analytics）の LCP P75 は **968 ms**。
- 壊れていないかは、**core に無い字をわざと太字にして rest が読まれること**（毒テスト）と、全 21 頁で rest が読まれないことの両方で見た。

![太字 700 の woff2 136 KB を core 63 KB（575 字・preload）と rest 84 KB に分ける。core に在る字は core だけを読み rest のリクエスト 0、core に無い字（万）のときだけ rest が読まれる](/images/font-700-core-rest-lcp/b1_core_rest.png)

## 何が LCP を待たせていたか

Lighthouse の LCP 要素は h1。h1 は `font-display: swap` なので最初はフォールバックで描かれますが、このサイトの計測では 700 の取得が h1 の描画経路に入っていて（Lighthouse の LCP 内訳は Render Delay が主）、700 を縮めて前後を比べる、という手順にしました。一般に swap が LCP を止めるという話ではなく、このサイトでの観測です。その太字 woff2 が 136 KB（自前 subset に切り替えて、Google Fonts への 53 リクエストを 3 に減らした直後の値）。本文の 400 が 142 KB で、700 もほぼ同じ大きさ——**本文で使う全字を太字にも入れていた**からです。

## 太字で実際に描かれる字を数える

推測で「見出しの漢字だけ」と決めずに、描画結果から集めました。

1. ローカルの preview で全 21 頁を開く
2. 各頁で `computed font-weight >= 600` の要素のテキストを集める
3. 重複を除いて 1 行に並べ、`scripts/fonts/bold-chars.txt` に保存（**316 字**）

これと、常に入れておく字（ASCII・かな全部・CJK 記号 U+3000-303F）の**和集合**が **575 字**＝core。Latin-1 補助や全角英数は太字で出ないので rest に回す。

```python
core_always = {c for c in always if ord(c) < 0x7F or 0x3000 <= ord(c) <= 0x30FF}
core = sorted({ord(c) for c in (bold_chars | core_always)} | {0x20, 0x3000})
rest = [u for u in unicodes if u not in set(core)]
sub("ZenKakuGothicNew-Bold.ttf", "700-core.woff2", core)   # 63,052 B
sub("ZenKakuGothicNew-Bold.ttf", "700-rest.woff2", rest)   # 84,372 B（分割時点。字を足して再生成すると増える＝09-16 時点 93,536 B）
```

subset は fontTools の `Subsetter`。生成器が `fonts.css` も書き出します。

## unicode-range の宣言順

```css
/* rest を先に・core を後に。同じ family／weight なら後の宣言が優先されるので、
   core に在る字は core を使い、rest は読まれない。core に無い太字が出たときだけ rest が読まれる */
@font-face { font-family: "Zen Kaku Gothic New"; font-weight: 700; font-display: swap;
  src: url("/fonts/zen-kaku-gothic-new-700-rest.woff2") format("woff2");
  unicode-range: U+2000-206F, U+3000-30FF, U+3400-4DBF, U+4E00-9FFF, U+FF00-FFEF; }
@font-face { font-family: "Zen Kaku Gothic New"; font-weight: 700; font-display: swap;
  src: url("/fonts/zen-kaku-gothic-new-700-core.woff2") format("woff2");
  unicode-range: /* 生成器が core の code point を U+XXXX-YYYY に畳んで書く */; }
```

`<head>` の preload は core だけ。rest は preload しない（読まれない頁が普通）。

## 毒テスト——「壊れていない」をどう見たか

分割で怖いのは 2 つ。core に無い字が見出しに出たときに**太字が出ない**こと（見た目が落ちる）と、core が効かず**毎回 rest まで読む**こと（速くならない）。両方を、条件を作って見ました。

- **毒**: core に無い「万」を見出しに置く → DevTools の Network で `700-rest.woff2` が読まれ、glyph が太字で出る（core に無い字は rest で描かれる＝見た目は落ちない）
- **正**: 21 頁すべてで `700-rest.woff2` が読まれない（core だけで足りている）

「速くなった」の数字だけ見て、毒を入れずに出すと、見出しに新しい漢字を足した日に静かに壊れます。core を更新する手順（bold-chars.txt を作り直して生成器を回す）は、生成器の冒頭コメントに書いてあります。

## 数字

| 項目 | 前 | 後 |
|---|---|---|
| 700 の woff2 | 136 KB（1 本・138,152 B） | core 63 KB ＋ rest 84 KB（rest は通常読まれない） |
| 初回転送（トップ） | 386 KB | 269 KB |
| Lighthouse mobile LCP `/works/repair/` | 2.4 s | **1.7 s** |
| Lighthouse mobile LCP `/` | 3.2 s | 2.9／1.8／3.0 s（3 回） |
| 実機 LCP P75（Cloudflare WA・訪問 39） | — | **968 ms**（Good 100%） |

⚠ Lighthouse の模擬低速 4G は回ごとに 1.2 s 揺れました（Render Delay が 1.1 s と 2.3 s の二峰）。模擬値で「2.0 秒以内」を名乗るのはやめ、実機の P75 で見ています。訪問 39 は母数が小さい（ほぼ本人と当方の閲覧）。

## うまくいかなかったこと

- 分割と同時に「表紙 PNG 55 KB → WebP」もやった（画素一致・11 KB）ので、転送 386 → 269 KB も LCP 2.4 → 1.7 s も 2 つの合算。**フォント単独の寄与とは言えない**（転送のフォント分は 136 − 63 ＝ 73 KB）。
- 分割後の合計は 63 ＋ 84 ＝ 147 KB で、分割前より増える。狙いは総量でなく、初回に読む量を 136 → 63 KB に減らすこと。
- 「見出しの字」を目で選ばず描画から集めたのは正解だったが、その 21 頁は 2026-09-13 時点の頁。頁を足したら core を作り直す運用が要る（毒テストがあるので、忘れても見た目は落ちない）。

## 手順として

1. LCP 要素を見る。h1 なら「何を待っているか」（フォント・画像・CSS）を Network で見る
2. 太字で**実際に描かれる字**を描画から集める（推測で漢字だけにしない）
3. core／rest に分け、`unicode-range` で core を後に宣言。preload は core だけ
4. 毒（core に無い字を太字に）で rest が読まれることを見る。正（全頁）で rest が読まれないことを見る
5. 模擬値で名乗らず、実機の P75 で見る

## 本家（検証の記録つき）

この記事の本家（検証環境・判定 PASS・証拠＝commit と月次指標）は Sumitsuke Lab → [太字の Web フォントを「見出しで実際に描かれる 316 字」に絞ったら LCP はどれだけ縮むか](https://sumitsuke.jp/via/zenn/lab/font-700-core-rest-lcp/)。

---

### AI の利用について

生成器（fontTools の subset・fonts.css の書き出し）と描画から太字の字を集める処理は AI（Claude Code）が書き、数字の照合と公開の判断は人間が行いました。この記事は AI が下書きし、数字はサイトの運用記録（runbook・metrics）から写しています。

### 記録と現物は Sumitsuke Lab に

このサイト自体の設計・検証の記録は [Sumitsuke Lab](https://sumitsuke.jp/lab/) に置いています。
