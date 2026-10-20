---
title: "WordPress に改ざんを 8 つ仕込んだら、照合の道具でも 4 つは見つからなかった"
emoji: "🔎"
type: "tech"
topics: ["WordPress", "WPCLI", "Playground", "セキュリティ", "保守"]
published: true
---


改ざんを疑ったとき、最初に `wp core verify-checksums` を回す、という手順が紹介されることがあります。WordPress Playground に 1 サイト建て、改ざんの形を 8 つ仕込みました（どれもコメント 1 行・何もしない関数・example.com のリンクだけの無害な印）。管理画面（ユーザー・プラグイン・投稿の一覧の画面）・本体の照合・プラグインの照合のどれで見つかるかを数えました。

結果は、**管理画面 1・本体の照合 1・プラグインの照合 1・どれでも見つからない 4・測れなかった 1** です（測れた 7 つのうち、見つかったのは 3 つ）。同じ仕込みで建て直した 2 回目も同じでした。

![改ざんの形 8 つ × 見つけ方 3 つ。見つかったのは 3 つ、どれでも見つからないのは 4 つ、home の書き換えは測れなかった](/images/wordpress-tamper-where-found/fig1_tamper_where_found.png)

## 照合の射程の外にあった 4 つ

| 仕込み | 管理画面（一覧） | `wp core verify-checksums` | `wp plugin verify-checksums --all` |
|---|---|---|---|
| 管理者を 1 人足す | **見つかった** | | |
| `wp-includes/formatting.php` に 1 行 | | **見つかった** | |
| Contact Form 7 のファイルに 1 行 | | | **見つかった** |
| `wp-content/uploads/` に PHP を 1 つ | | | |
| 投稿の本文に `display:none` のリンク | | | |
| 自作プラグインのファイルを書き換える | | | |
| 自作プラグインの見出し（`Plugin Name`）を消して書き換える | | | |
| `home` を書き換える | 測れなかった（下のつまずき 3） | | |

本体の照合は、書き換えた `formatting.php` だけを報告しました。

```text
Warning: File doesn't verify against checksum: wp-includes/formatting.php
Error: WordPress installation doesn't verify against checksums.
```

`uploads` に置いた PHP は報告されませんでした。本体の照合は、WordPress.org が出している本体の数値と、手元のファイルを突き合わせる道具です（[公式の説明](https://developer.wordpress.org/cli/commands/core/verify-checksums/)）。照合の[ソース](https://github.com/wp-cli/checksum-command/blob/main/src/Checksum_Core_Command.php)を読むと、数値に無いファイルも `File should not exist` として報告しますが、`wp-content` で始まるパスは最初から外しています。`uploads` は `wp-content` の中なので、射程の外でした（`wp-includes` に足したファイルが報告されるかは、今回は測っていません）。

プラグインの照合の最後の行はこうでした。

```text
Warning: Could not retrieve the checksums for version 1.0 of plugin site-helper, skipping.
Error: Only verified 2 of 4 plugins (1 failed, 1 skipped).
```

数えた 4 つは Akismet・Contact Form 7・Hello Dolly・自作の site-helper です。自作のものは公式の数値が無いので飛ばされ、書き換えは見えません。**見出しを消した自作プラグインは、4 つにも入っていません**。管理画面のプラグイン一覧からも消えました。WordPress が見出しでプラグインを数えるので、見出しが無いファイルは「プラグインでない」扱いになります。

![プラグインの照合が数えた 4 つ: 照合できた 2・食い違い 1・飛ばした 1。見出しを消した自作は数に入らない](/images/wordpress-tamper-where-found/fig2_plugin_verify_counts.png)

## つまずいたこと

**1. 照合が公式のチェックサムを取れなかった**: Playground の中で `wp core verify-checksums` を回すと、こう止まりました。

```text
Failed to get url 'https://api.wordpress.org/core/checksums/1.0/?version=7.1.2&locale=en_US':
cURL error 77: error setting certificate verify locations: CAfile: /etc/ssl/certs/ca-certificates.crt
```

Playground の中に証明書の束が無いためです（この止まった試しのログは残していません）。`--insecure` で証明書の確かめを切る手もありますが、改ざんを確かめる道具の取得で確かめを切るのは避けました。手元の証明書の束（Python の certifi のもの）を `--mount-dir <手元のフォルダ> /etc/ssl/certs` で差し込み、確かめたまま取れました。仕込む前は `Success: WordPress installation verifies against checksums.` と `Success: Verified 3 of 3 plugins.` です。

**2. 食い違いを見つけると、blueprint ごと止まった**: 照合は食い違いを見つけると終了コード 1 を返します。blueprint の手順が 1 つ失敗すると、後ろの手順（プラグインの照合）は走りません。照合を `wp eval-file` の中で 1 本ずつ、`WP_CLI::runcommand()` に `exit_error => false` を渡して呼び、出力と終了コードをファイルに残しました。

```php
$r = WP_CLI::runcommand('core verify-checksums', ['return' => 'all', 'exit_error' => false, 'launch' => false]);
file_put_contents('/wordpress/_out/core_verify.json', json_encode(['code' => $r->return_code, 'stdout' => $r->stdout, 'stderr' => $r->stderr]));
```

**3. `home` を書き換えたのに、`get_option('home')` は元のままだった**: 予想は「設定 > 一般で見える」でした。結果を見て道具を疑い、もう 1 回走らせました。`update_option('home', …)` は真を返し、データベースの値は書き換わっています。ところが `get_option('home')` は元の値を返しました。Playground は `WP_HOME` を定数で決めていて（`--site-url` の値）、定数がデータベースの値より勝ちます。この環境では「見えるか」を測れないので、表から分けました。本物のサイトでも、`wp-config.php` に `WP_HOME` を書いていると同じ形になるはずです（データベースの書き換えは見えず、効かない・⚠ 本物のサーバーでは確かめていない）。

## 照合の外を見る手

照合で見えなかった 4 つは、別の場所を見る必要があります。どれも今回は**測っていない**手の例です。

- `uploads` の中の PHP を探す（ファイルの一覧で `.php` を数える）
- 投稿の本文を、一覧の抜粋ではなく 1 本ずつ生の HTML で見る（`display:none` のリンク。今回の管理画面の見方は一覧の題と抜粋だけ）
- 自作・購入のプラグインは、手元の元のファイルと突き合わせる（公式の数値が無い）
- 見出しの無い PHP がプラグインの置き場にあるかを、ファイルの一覧で見る（管理画面の一覧に出ない）

## 言わないこと

- 「照合を回せば改ざんは全部見つかる」とは書きません。測れた 7 つのうち 2 つでした
- 仕込んだ形を「よくある改ざん」とは言いません。当方が決めた 8 つです
- 本物のサーバー・ほかのセキュリティの道具では確かめていません。データベースは SQLite です

この記事の本家（仕込みと測る道具・2 回分の照合の出力・`home` を測れなかった記録）は Sumitsuke Lab → [WordPress の改ざんを仕込み、3 つの見つけ方と射程の外で数える（検証の記録つき）](https://sumitsuke.jp/via/zenn/lab/wordpress-tamper-four-ways-measured/)。

### AI の利用について

仕込み・測る道具・集計は AI（Claude Code）が書いて走らせました。予想と判定の決まりは測る前にコミットで凍結しています（`a91ecf10`）。動く悪性のコードは書いていません。公開の判断は人が行いました。

### 関連

事業者の方向けに、業者に頼む前に確かめることを書いた読み物 → [サイトが改ざんされたかもしれない。業者に頼む前に確かめる 5 つ](https://sumitsuke.jp/via/zenn/works/guide/site-may-be-tampered/)
