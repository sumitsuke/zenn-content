---
title: "引き継いだ WordPress を管理画面だけで点検する——WP-CLI を足しても、5 項目の判定は 1 つも変わらなかった"
emoji: "🧰"
type: "tech"
topics: ["WordPress", "WPCLI", "Playground", "保守", "PHP"]
published: true
---


WordPress の保守を引き継いだ初日に、何を見れば「分かった」と言えるか。よく見る確認の一覧を、1 つのサイトに当てて数えてみました。WordPress Playground に「引き継いだ状態」のサイトを建て、7 つの問題を仕込みます。その一覧は見せずに、別のセッションに管理画面の手順だけで確かめてもらいました。そのあと、当方が WP-CLI を足しました。

結果、5 項目の判定（確認できた／管理画面では確認できない／対象外）は、**CLI を足しても 1 つも変わりませんでした**。変わったのは手数だけです。そして、実測の途中で当方が 3 回つまずきました。この記事は、そのつまずきから書きます。

![5 項目を 7 つの問いに分けた表。管理画面で分かったのは 3（管理者は誰か・どの頁か・版）、分からなかったのは 4（今も関わっているか・いつから・バックアップ・契約の名義）。WP-CLI を足しても同じ](/images/wordpress-handover-admin-vs-wpcli/fig1_five_items_three_values.png)

## つまずき 1: はみ出しを innerWidth で測ると見落とす

仕込みの 1 つは、固定ページ「料金表」に入れた幅 1,600px の表です。スマホでは横にはみ出します。確かめる側（エージェント）には、当方が「幅 375 にして `document.documentElement.scrollWidth > innerWidth` を測る」と指示していました。

結果は `false` でした。幅 375 の真似では、はみ出した分だけ `innerWidth` も 758 に広がっていました。確かめた側が `clientWidth`（375）と比べ直して、初めてはみ出しが出ました（`scrollWidth` 758 > `clientWidth` 375）。

凍結した手順書ではなく、当方が渡した指示の書き方の誤りです。見落とすところでした。

## つまずき 2: Playground の中の WP-CLI

手元の PC には PHP も Docker もありません。Playground（`@wp-playground/cli` 3.1.55）で建てると、DB は SQLite です（サイトヘルスでは `WP_MySQL_On_SQLite`）。WP-CLI を使うまでに 3 回失敗しました。

1. **別の口からは同じサイトに繋がらない**: サーバーを止めて `run-blueprint` や `php` で同じフォルダを開くと、`Error connecting to the SQLite database.` か `Error establishing a database connection` になりました
2. **`wp-cli` の手順は出力を残さない**: blueprint の `wp-cli` の手順は、出力を `php://stdout` で Playground に返すだけで、ファイルには残りませんでした（`/tmp/stdout` を写しても 0 バイト）
3. **`wp --info` は Playground ごと落ちた**: `Aborted()`・`Error when executing the blueprint step #39: unreachable`

通ったのはこの形です。サーバーを起動するときの blueprint の中で、一度 `wp-cli` の手順を走らせて `/tmp/wp-cli.phar` を置かせます。そのあとは `runPHP` で同じ呼び方をし、`STDOUT` をファイルへ向けます。

```php
<?php
putenv('SHELL_PIPE=0');
$GLOBALS['argv'] = array_merge(
  ['/tmp/wp-cli.phar', '--path=/wordpress', '--require=/tmp/playground-wp-cli-overrides.php'],
  ['plugin', 'list', '--fields=name,status,version,update,update_version']
);
define('STDIN', fopen('php://memory', 'r'));
define('STDOUT', fopen('/wordpress/_cli/C2.out.txt', 'wb'));   // 手元のフォルダに割り当てた先
define('STDERR', fopen('/wordpress/_cli/C2.err.txt', 'wb'));
require '/tmp/wp-cli.phar';
```

試した 13 本のうち、使える出力を返したのは 11 本でした。`wp --info` は上のとおり落ち、`wp db size` は SQLite では `0 B` と返って使えませんでした。

## つまずき 3: 「backup」で探すと本体の処理が引っかかる

バックアップの有無を CLI で見るとき、予約の処理（`wp cron event list`）を「backup」で探しました。13 本のうち 1 本、`wp_delete_temp_updater_backups` が引っかかります。これは WordPress 本体の、更新の一時的な控えを消す処理です。サイトのバックアップではありません。名前だけで「バックアップの仕組みがある」と読むところでした。

## 結果

仕込みと、確かめた結果です。管理画面は目隠しの別セッション（AI）が確かめ、手順 10・開いた画面 17 でした。かかったのは約 4 分ですが、これは AI が操作した時間で、人が同じ作業にかかる時間ではありません。

①と②は、1 つの項目の中に「分かる」と「分からない」が混ざりました。5 つの項目を 7 つの問いに分けると、管理画面で確認できたのは 3 つ（管理者は誰か・どの頁か・版）、分からなかったのは 4 つ（今も関わっているか・いつからか・バックアップ・契約の名義）です。

| 項目 | 管理画面 | CLI を足す |
|---|---|---|
| ① 管理者は誰か | 確認できた（3 人・名前・メール）。今も関わっているかは確認できない（最終ログインの欄が無い） | 登録日が足された。関わりは確認できない |
| ② どの頁で・いつから | どの頁＝確認できた（幅 375 で料金表だけはみ出す）。いつから＝確認できない | 最後に変えた日時は出る。崩れは見えない（描画しない） |
| ③ バックアップ | 管理画面では確認できない（「無い」と「サーバー側で取っている」を分けられない） | 予約の処理にも無い。サーバー側は分からない |
| ④ 版 | 確認できた（3 画面） | 確認できた（`wp plugin list` 1 本） |
| ⑤ 名義と更新日 | 対象外 | 対象外 |

事前に置いた基準は「確認できた項目が 1 つ以上違えば、CLI を足す価値を書く」でした。違いは 0 です。CLI だけで点検すると、②の崩れた頁には気づけません。

![変わったのは手数だけ。版を確かめる手数は 3 画面→1 コマンド、判定が変わった問いは 7 問中 0。WP-CLI は 13 本中 11 本が使えた](/images/wordpress-handover-admin-vs-wpcli/fig2_admin_vs_cli_steps.png)

仕込んだ「古いアドレス」（管理者のメールとフォームの送信先）は、管理画面でも CLI でも見えました。ただ、そのアドレスが今も受け取れるかは、どちらでも分かりません。

## 言わないこと

- 「管理画面では足りない」「CLI は要らない」と一般化しません。1 サイト・当方が仕込んだ 7 つ・SQLite・反復 1 回（探索的）の結果です
- Playground に出たもの（WP_DEBUG が有効・HTTPS なし・DB 名が `database_name_here`）を、本物のサーバーの話として書きません
- 特定のプラグインを危ないとは言いません。古い版を仕込んだのは当方です
- 「更新すれば直る」は書きません。更新で見た目が変わるかは測っていません

この記事の本家（blueprint・仕込みの一覧・手順 2 本・目隠しの記録・CLI の出力）は Sumitsuke Lab → [引き継いだ WordPress の点検 5 つを手元で再現して測る（検証の記録つき）](https://sumitsuke.jp/via/zenn/lab/wordpress-handover-five-checks-measured/)。

### AI の利用について

サイトを建てて仕込んだのも、CLI を回したのも AI（Claude Code）です。管理画面の確かめは、仕込みを知らない別の AI のセッションが行いました。仕込みと手順は確かめる前に凍結しています。公開の判断は人が行いました。

### 関連

事業者の方向けに、同じ実測を「頼む前に確かめる 5 つ」として書いた読み物 → [WordPress のサイトを直してほしい。頼む前に確かめる 5 つ](https://sumitsuke.jp/via/zenn/works/guide/wordpress-before-asking-repair/)
