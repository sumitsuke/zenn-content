---
title: "WordPress の URL を SQL で置き換えたら、設定 3 つが読めなくなり 1 つは空で上書きされた"
emoji: "🔁"
type: "tech"
topics: ["WordPress", "WPCLI", "Playground", "移行", "PHP"]
published: true
---


サイトを http から https へ移すとき、データベースの URL を `UPDATE … SET option_value = REPLACE(…)` で書き換える手順は、今も手順の 1 つとして紹介されていることがあります。WordPress Playground に 1 サイト建て、URL を含む設定を 3 つ仕込んで、この手順と `wp search-replace` を比べました。

測っている途中で、いちばん困ることが起きました。**読めなくなったウィジェットの設定が、WordPress を読み込んだあと、エラーも出ないまま空の値で上書きされていた**のです。読めないだけなら、元の値はデータベースの中に残っています（逆の置き換えで戻るかは試していません）。上書きされると、元の値はデータベースから消えます。

![URL の長さが同じなら SQL でも 0 行。1 字でも違うと SQL の REPLACE では 3 つとも読めなくなり、wp search-replace は 0 行](/images/wordpress-url-replace-serialized-length/fig1_conditions_methods.png)

## 起きたこと: 読めない → 空で保存

ウィジェットの本文は、データベースに PHP の配列を文字にした形（シリアライズ）で入っています。文字列の前に長さの印が付きます。

```text
s:4:"text";s:50:"<a href="http://old-site.example/about/">about</a>";
```

`http` を `https` に置き換えると中身は 51 字になりますが、`s:50` はそのままです。長さの印と中身が合わない値は、`unserialize()` が読めず `false` を返します。

置き換えの直後に数えると、読めない行は 3 つでした（ウィジェット・テーマのカスタマイズ・自作プラグインの設定）。ところが、次に WordPress を読み込んでから数え直すと **2 つに減っていました**。直ったのではありません。ウィジェットの行だけが、本文ごと消えた空の値に書き換わっていました。

```text
置き換えの前:            a:2:{i:2;a:2:{s:5:"title";…s:4:"text";s:50:"<a href=…>about</a>";}s:12:"_multiwidget";i:1;}
読み直した後（保存済み）: a:1:{s:12:"_multiwidget";i:1;}
```

保存した出力（末尾 4,000 字）に PHP のエラーはありませんでした。`get_option()` は既定の値を返し、設定が無いのと同じに見えます。どの処理が空の値を書いたかは切り分けていません（WordPress を読み込んだ前後の差を見ただけです）。

![ウィジェットの生の値: 置き換えの前は本文あり → 置き換えの直後は長さの印が合わず読めない → 読み直した後は空の既定で保存](/images/wordpress-url-replace-serialized-length/fig2_widget_overwritten.png)

## 3 条件 × 2 手段の結果

旧 URL は `http://old-site.example`（23 字）です。置き換える前に、旧 URL を含む行は 15 でした（設定 5・投稿のメタ 1・本文 3・GUID 6）。

| 新しい URL | SQL の REPLACE | wp search-replace |
|---|---|---|
| 同じ長さ（`http://new-site.example`・23 字） | 読めない 0・取得できない設定 0 | 0・0 |
| 1 字増える（`https://old-site.example`） | **読めない 3・取得できない設定 3** | 0・0 |
| 大きく違う（`https://www.new-domain-example.com`・34 字） | **読めない 3・取得できない設定 3** | 0・0 |

「取得できない設定」は、`get_option()` が仕込んだ値ではなく既定の値を返した数です。そのうち元の値まで消えた（空で上書きされた）のは、ウィジェットの 1 つです。

- 旧 URL が残った行は、6 通りとも 0（GUID も置き換わった）
- 同じ仕込みから建て直した 2 回目も、6 マスとも同じでした
- 測る前に凍結した予想と、6 マスとも同じでした

今回の ASCII の URL と 3 つの仕込みでは、長さ（バイト数）が同じなら SQL でも壊れませんでした。壊れたのは「SQL で置き換えたから」ではなく、**長さが変わって、シリアライズの長さの印と中身が合わなくなったから**です。

ただし、「長さが同じだから SQL の `REPLACE` を使ってよい」とは判断しません。長さの印は文字数ではなくバイト数で、日本語を含む URL やほかのデータまで同じとは言えません。実務では、シリアライズを扱える手段を使います。

## 実務ですること

1. 置き換える前に、データベースの写しを取る（`wp db export`）
2. `wp search-replace` を `--dry-run` で回し、どの表で何件置き換わるかを見る（公式の説明: 置き換えを全部回して報告を出し、保存しない）
3. 対象を確かめてから、`--dry-run` を外して回す。GUID（投稿の識別子）は、公式の例にならって `--skip-columns=guid` で外すかを決める（今回の実測は外さずに回した）

```bash
wp db export before-replace.sql
wp search-replace 'http://old-site.example' 'https://old-site.example' --skip-columns=guid --dry-run
wp search-replace 'http://old-site.example' 'https://old-site.example' --skip-columns=guid
```

公式の説明は、`search-replace` が PHP のシリアライズを扱うと書いています。

## つまずいたこと

**`--php=8.3` を付けたのに PHP 8.5.10 で動いていた**: `wp-playground-cli run-blueprint --php=8.3` で起動したのに、`PHP_VERSION` は 8.5.10 でした（この試しのログは残していません）。blueprint の中に `"preferredVersions": {"php": "8.3"}` を書いて、8.3.33 になりました（こちらは生の出力に残っています）。版を固定したつもりの実測は、中で版を印字して確かめます。

**`search-replace` の「396 replacements」は、置き換えた数ではなかった**: 3 条件とも `Success: Made 396 replacements.` でした。表を見ると、`wp_options` の `option_name`（128）や `autoload`（128）まで数えられています。旧 URL を含んでいた行は 15 です。数が実数なのは、シリアライズを解いて置き換える列（`Type` が `PHP` の行＝設定 5・メタ 1）だけでした。SQL の `REPLACE` の `affected` も、設定の表で 128 と返りました。Playground の SQLite の差し込みが、一致した行ではなく全部の行を返している、と読んでいます（⚠ MySQL では確かめていない）。

**サイトの URL は定数で決まっていた**: データベースの `siteurl` と `home` を書き換えても、サイトの動きは変わりませんでした。Playground が `WP_HOME`・`WP_SITEURL` を定数で決めているためです。なので「サイトが開けなくなる」はこの環境では確かめられず、数えたのは設定の 3 つと行の数だけです。

## 言わないこと

- MySQL での結果とは言いません。SQLite（Playground）の 1 サイト・当方が仕込んだ 3 つの設定です
- 「`search-replace` なら必ず安全」とは書きません。この仕込みで 0 だった、までです
- 「長さが同じなら SQL でよい」とも書きません。今回の ASCII の URL で壊れなかった、までです
- 特定の移行のプラグインやサービスを評価しません

この記事の本家（仕込みと測る道具・blueprint・2 回分の生の出力）は Sumitsuke Lab → [WordPress の URL の置き換えで何が壊れるかを、長さの差で測る（検証の記録つき）](https://sumitsuke.jp/via/zenn/lab/wordpress-url-replace-length-measured/)。

### AI の利用について

仕込み・測る道具・集計は AI（Claude Code）が書いて走らせました。予想と判定の決まりは測る前にコミットで凍結しています（`a91ecf10`）。公開の判断は人が行いました。

### 関連

事業者の方向けに、移す前に確かめることを書いた読み物 → [サーバーやドメインを移したい。頼む前に確かめる 5 つ](https://sumitsuke.jp/via/zenn/works/guide/before-moving-server-or-domain/)
