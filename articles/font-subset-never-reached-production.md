---
title: "subset フォントを作り直しても本番に届いていなかった——同名 URL と 1 年キャッシュで版が混ざり、太字の漏れで分割が崩れた"
emoji: "🔤"
type: "tech"
topics: ["webfont", "cloudflare", "cache", "performance", "astro"]
published: true
---


> 単位: 本文の KB は 1,000 B（`Content-Length` の値）。外部精査の引用は KiB（1,024 B）のまま書きます（102,912 B＝102.9 KB＝100.5 KiB）。

前編（[日本語 Web フォントの太字を見出しの字だけに絞る](https://zenn.dev/tauridev/articles/font-700-core-rest-lcp)）で、太字フォントを core（見出しの字）と rest（残り）に分けて 136→63 KB にした話を書きました。その後 2 回、設計を変えて subset を作り直しました。**どちらも本番には届いていませんでした。** 気づいたのは、外から転送量を数えた精査が、700-core は 62 KiB、700-rest は 94 KiB が全頁で読まれていると報告してきたときです。手元のファイルは 115 KB、rest は読まれないはずでした。

**この記事の位置づけ**（2026-09-26 追記）

- 既に知られていること: 長くキャッシュさせるファイルは、中身が変わったら URL を変える（ハッシュを付ける）のが定石です（[web.dev](https://web.dev/articles/http-cache)）。
- この記事で新しく示すこと: 作り直した subset が 2 回とも本番に届かず、版の混ざった状態で太字の漏れが分割を崩していたことを、外から転送量を数えて見つけた数字。
- 当てはまる範囲: 当方のサイト 1 つ（Cloudflare Pages・自前の subset）。

## 先に結論

1. **同じ URL に `public, max-age=31536000` を付けたまま中身を更新すると、CDN はキャッシュに残っている間（最大 1 年）その URL を fresh として、origin に再検証せず返し得る。** 当サイトでは実際に旧版の HIT を確認し、しかも**3 ファイルが 2 つの別の日（09-17 と 09-18）の版**で配られていた（当方の地点: 700-core は 09-17 版・400 と 700-rest は 09-18 版。別の地点の精査では 400 が 134 KiB＝09-12/13 版のサイズ、rest が 94 KiB＝09-16 版のサイズ、700-core は 62 KiB＝63 KB 系のどれか）。「古い」ではなく「混ざる」。core と rest が別の日の build なら、CSS の unicode-range と woff2 の中身がずれ得る＝分割の前提が崩れ得る（字が落ちた・代替フォントになった、といった描画への影響は観測していません）。
2. **core/rest 分割は、太字で描かれる字が 1 字でも core に無いと、その頁で rest（103 KB）が丸ごと落ちる。** 共通ヘッダーの「一覧」の **覧**（全頁）と h2 の **必**（2 頁）が漏れていて、全頁が rest を読んでいた。「その頁では rest を読ませない」という狙いが崩れていた。
3. 直しは 3 つ。URL に中身の sha1 を付ける（`?v=…`・クエリはキャッシュキーに入る）／太字で描かれる字を生成物から数えて core に無ければ build を止めるチェック／400 も同じ形で core（記事以外に出る字）と rest（記事だけの字）に分ける。結果、Works の頁はフォント **280 KB・rest 0**（本番の resource timing）。

`immutable` は CDN の話ではありません。Cloudflare の公式文書は “This directive has no effect on public caches like Cloudflare, but does change browser behavior.” と書いています。効いていたのは `max-age` と同名 URL です。`immutable` はブラウザが再検証をやめる指示で、こちらはこちらで「同名のまま」を長引かせます。因果を分けて書きます。

## 起きたこと（数字）

### 手元と本番が違う

`git log` × `git ls-tree -l` で 700-core の履歴を 27 commit 並べると:

| 日時 | commit | 700-core |
|---|---|---|
| 09-13 09:38 | `7a9078e` | 63,052 B |
| 09-17 14:17 | `10a62e1`（07:32 `041d254` も同バイト。Age から逆算して 14:17 の版） | **63,100 B** |
| 09-18 11:20 | `8dd3329` | 75,136 B（設計変更 1＝core に見出しの字を足した） |
| 09-19 11:01 | `f1ace58` | 115,080 B（設計変更 2＝太字のチェックで漏れ 298 字を足した） |

本番の無印 URL に `curl -I`（09-19 12:5x）:

| ファイル | Content-Length | Age | 版 |
|---|---|---|---|
| 700-core.woff2 | 63,100 | 166,396 秒 | 09-17 |
| 400.woff2 | 165,704 | 7,273 秒 | 09-18 18:38 `b0780fa`（09-19 11:01 まで同バイト） |
| 700-rest.woff2 | 102,912 | 7,273 秒 | 09-18 |

Age 166,396 秒を 12:5x から引くと 09-17 14:4x＝`10a62e1`（14:17）のデプロイ直後です。700-core はこの版が 2 日近く配られ、その後の 16 commit（設計変更 2 回を含む）は届いていませんでした。同じ日の昼に別の地点から精査した観測は「400＝134 KiB・rest＝94 KiB・700-core＝62 KiB」。134 KiB は 09-12/13 版のサイズ、94 KiB は 09-16 版のサイズに当たります（700-core の 62 KiB は 63 KB 系＝09-13〜09-18 07:07 のどれかで、KiB 1 桁では日を特定できません）。**別の地点では、当方の地点とも異なる旧版のサイズを観測した**、が言える範囲です。

![同じ URL・1 年キャッシュで配られていた版の日。700-core は当方の地点で 09-17 版・外部の地点は 62 KiB（63 KB 系のどれか）、400 は 09-18 版と 09-12/13 版のサイズ、700-rest は 09-18 版と 09-16 版のサイズ。リポは 09-19。直し＝URL に sha1](/images/font-subset-never-reached-production/fig1_version_mix.png)

woff2 は毎 commit 数バイトずつ変わります（63,024〜63,108）。「2 回作り直した」ではなく「毎回変わるファイルを、同じ名前で 1 年キャッシュに置いていた」が正確です。

### 太字 2 字

前編の設計は「core を後に宣言して unicode-range で当てる。core に無い字が太字で出たときだけ rest が落ちる」でした。それ自体は正しく動いていて、**落ちる条件を自分で作っていた**のが問題でした。

- 共通ヘッダーのナビ「読み物の一覧」「検証記録の一覧」＝太字。**覧** が core に無い → 全頁で rest。
- トップと Works 索引の h2「納品のとき、必ず残す 4 つ」＝**必** が core に無い → 2 頁で rest（ただし覧で既に全頁）。

core の字は前編で「描画して computed font-weight を読む」方法で 316 字を集めたもので、その後に足した語は入っていませんでした。チェックは「全体の subset に無い字」しか見ていなかったので、太字の部分集合の漏れは緑のまま通りました。

## 直し

### 1. URL に版を付ける（生成器で）

subset 生成器（fontTools）が woff2 を書いたあと、各ファイルの sha1 先頭 8 桁を `versions.json` に書き、`fonts.css` の `url()` と HTML の `<link rel="preload">` に `?v=<hash>` を付けます。手で付けると忘れるので生成器の仕事にしました。

```python
_ver = {n: hashlib.sha1(open(os.path.join(OUT, n), 'rb').read()).hexdigest()[:8]
        for n in sorted(os.listdir(OUT)) if n.endswith('.woff2')}
css = re.sub(r'url\("/fonts/([^"?]+\.woff2)"\)',
             lambda m: f'url("/fonts/{m.group(1)}?v={_ver[m.group(1)]}")', css)
```

Cloudflare の既定のキャッシュキーにはクエリ文字列が入るので、版ごとに別の URL＝別のキャッシュになります。`_headers` の `immutable` はそのまま（同じ URL の中身は本当に変わらなくなったので）。

デプロイ後の確認: `curl -I …700-core.woff2?v=5b9d4c64` → `Content-Length: 115088`・`cf-cache-status: MISS`（初回）。

### 2. 太字の字を生成物から数えるチェック

`check-zones.mjs`（build 後に dist を検査する自作のチェック）に 1 段足しました。h1〜h3・strong・b・th・dt・summary と、CSS で `font-weight: 700` を当てているクラスの中の文字を集め、`bold-core-chars.txt`（生成器が書く core の字の一覧）に無ければ赤。

```js
const tagRe = new RegExp(`<(h[1-3]|strong|b|th|dt|summary)\\b[^>]*>([\\s\\S]*?)<\\/\\1>|<(\\w+) class="(?:[^"]*\\s)?(?:${BOLD_CLASSES.join('|')})(?:\\s[^"]*)?"[^>]*>([\\s\\S]*?)<\\/\\3>`, 'g');
for (const ch of text) if (ch.codePointAt(0) >= 0x80 && !boldCore.has(ch)) boldMissing.set(ch, ...);
if (boldMissing.size) red.push(`フォント: 太字の字が 700-core に無い ${boldMissing.size} 個 …`);
```

初回の出力は「700-core に無い 298 字 覧経屋号廃止必…」。Lab 記事の `strong` の字が大半でした。全部 core に足すと core は 75→115 KB、rest は 103→63 KB。チェックは全頁の生成物で漏れ 0 を確かめ、本番の転送はトップ・Lab 記事・Works（pricing）の 3 頁の resource timing で rest 0 を確認しました。多めに拾う側（dt・summary も拾う）に倒した近似です＝core が少し太るだけで、漏れの方向には外れません。

![太字 2 字の漏れで全頁が rest を読んでいた。漏れていた字＝覧（共通ヘッダー・全頁）・必（h2・2 頁）→ 全頁で 700-rest 103 KB。チェックが見ていたのは全体の subset だけ。直し＝太字の字を dist から数えるチェック（初回 298 字）。結果＝Works 頁 280 KB・rest 0](/images/font-subset-never-reached-production/fig2_two_chars.png)

### 3. 400 も分ける

同じ仕組みで 400（本文）も、記事以外に出る字（1,458 字・142 KB）と記事だけに出る字（177 字・29 KB）に分けました。Works の頁が読むのは 700-core 115・400-core 142・500 22 の **280 KB**、rest はどちらも 0（本番の `performance.getEntriesByType('resource')`）。

## うまくいかなかったこと

- **手元の `git` を見て「更新した」と思っていた。** 本番の `Content-Length` を一度も並べていなかった。同名ファイルで長い max-age を付けるなら、デプロイ後に本番のバイト数を並べるのは必須の 1 行でした。
- 09-18 の設計変更 1（core に見出しの字を足す）は、届いていない上に **覧・必 が入っていなかった**ので、届いていても rest は落ちていました。2 つの欠陥が重なっていて、片方だけ直しても転送量は変わらなかったはずです。
- 太字のチェックの初回は 1 字だけ赤が残り、それは nbsp（U+00A0）でした。core の「常に入れる範囲」に入れて閉じました。
- 「外部の精査が無ければ気づかなかったか」は言い切れません（Lighthouse の転送量でも見えた可能性）。ただ、自分では 6 日間気づかなかったのは事実です。

## 3 層で並べる 1 表

フォント以外の CSS・JS・画像にも同じ表が使えます。同名で長いキャッシュを付けている資産は、この 3 列が揃って初めて「届いた」と言えます。

| 資産 | 手元（bytes・sha） | CDN（Content-Length・Age・cf-cache-status） | ブラウザ（transferSize） |
|---|---|---|---|
| 700-core | 115,080 | 63,100・166,396・HIT（09-17 版） | 未測定 |
| 400 | 165,732 | 165,704・7,273・HIT | 未測定 |
| 700-rest | 63,104 | 102,912・7,273・HIT | 未測定 |

ブラウザ列は、直す前（09-19 12:5x）には測っていません。その版はもう取り戻せないので、空欄のままにしました。この表は形の見本で、ブラウザ列の数字はありません。直したあとの値は、Works（pricing）の頁で 700-core 115,392・400-core 141,876・500 22,808 B（合計 280,076 B）です。

手元の 3 ファイルと CDN の 3 ファイルは、揃っていませんでした。CDN が返した 3 ファイルは 2 つの別の日（09-17 と 09-18）の版で、手元（09-19）とも違いました。

## 測っていない範囲

- ブラウザ側のキャッシュ動作は Chromium 系 1 種類で見ただけです。
- 観測地点は 2（当方と、精査した相手）。相手側は転送量（KiB）だけで `Content-Length`・colo は無いので、版の日は「サイズが当たる commit」までです。Cloudflare のどの階層で版が分かれたかは追っていません。
- LCP の実値は未計測（転送量の数字まで）。

### AI の利用について

subset 生成器・太字のチェック・この記事の下書きには AI（Claude Code）を使っています。数字は `git ls-tree`・`curl -I`・ブラウザの resource timing から写し、判断（因果の分離・チェックの設計）は人が行いました。案件の情報は含みません（自サイトの数字だけ）。

### 関連

- 前編: [日本語 Web フォントの太字を見出しの字だけに絞る（136→63 KB）](https://zenn.dev/tauridev/articles/font-700-core-rest-lcp)
- 本家（検証の記録つき）: https://sumitsuke.jp/via/zenn/lab/font-subset-cache-version-mix/

---

Sumitsuke は、AI や外注で作ったものの点検と修理、業務自動化、検証を受託しています。「軽くしたはずなのに軽くならない」の切り分けは → https://sumitsuke.jp/works/repair/
