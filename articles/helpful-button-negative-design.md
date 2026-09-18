---
title: "静的サイトに「役に立った」を最小で付ける——守らないものを先に決める"
emoji: "👍"
type: "tech"
topics: ["Cloudflare", "D1", "Astro", "設計", "技術記事"]
published: false
---


自社サイトの検証記事（22 本）の末尾に「この検証は役に立ちましたか？」のボタンを付けました。Cloudflare の外の SaaS も認証も足さず、Cloudflare Pages Functions＋D1（無料枠）だけで、保存するのは slug と件数の 2 列だけ。実装から本番の E2E まで同日。

小さくできたのは、作り込んだからではなく、**「何を守らないか」を先に決めた**からです。

![守る（加算の取りこぼし・実在 slug・障害時も読める・D1 に IP・UA・時刻を保存しない）と守らない（一人一票・再投票・監査利用・不正分析）。加算は 1 文・並列 20 で 20。D1 に IP・UA・時刻は保存しない](/images/helpful-button-negative-design/fig1_keep_drop.png)

## 守る／守らない（先に決めた 1 枚）

| 守る | 守らない |
|---|---|
| 加算の取りこぼし（同時押しで数が減らない） | 厳密な一人一票 |
| 存在する記事の slug だけ数える（ゴミ行を作らない） | incognito や別ブラウザからの再投票 |
| JS が無い・API が落ちている・未結線でも記事は読める | ライク数の監査・実績や営業への利用 |
| D1 に IP・UA・時刻を保存せず、投票判定にも使わない（Cloudflare 自体のリクエスト処理・ログは本記事の範囲外） | 不正投票の分析 |

右列を守ろうとすると、IP のハッシュ・レート制限・ログ・通知……と増えていく。右列を「対象外」と決めた瞬間、左列は Functions 約 30 行（注記込み 31 行）で足りた。

## 実装（Pages Functions＋D1）

```ts
// functions/api/like/[slug].ts（抜粋）
const SLUG = /^[a-z0-9][a-z0-9-]{1,80}$/;

async function isLabSlug(env, request, slug) {
  // 記事が実在する slug だけ数える（ゴミの行を作らない）。自分の静的ファイルに HEAD で聞く
  const r = await env.ASSETS.fetch(new Request(new URL(`/lab/${slug}/`, request.url), { method: 'HEAD' }));
  return r.ok;
}

export const onRequestGet = async ({ params, env }) => {
  if (!env.LIKES) return json({ ok: false, reason: 'unbound' }, 503);   // 未結線なら 503。画面には何も出ない
  const slug = String(params.slug ?? '');
  if (!SLUG.test(slug)) return json({ ok: false }, 400);
  const row = await env.LIKES.prepare('SELECT n FROM likes WHERE slug = ?').bind(slug).first();
  return json({ ok: true, n: row?.n ?? 0 });
};

export const onRequestPost = async ({ params, env, request }) => {
  if (!env.LIKES) return json({ ok: false, reason: 'unbound' }, 503);
  const slug = String(params.slug ?? '');
  if (!SLUG.test(slug)) return json({ ok: false }, 400);
  if (!(await isLabSlug(env, request, slug))) return json({ ok: false }, 404);
  const row = await env.LIKES
    .prepare('INSERT INTO likes (slug, n) VALUES (?, 1) ON CONFLICT(slug) DO UPDATE SET n = n + 1 RETURNING n')
    .bind(slug).first();
  return json({ ok: true, n: row?.n ?? 1 });
};
```

表は `likes(slug TEXT PRIMARY KEY, n INTEGER)` の 1 つ。

D1 の無料枠は 2026-09-18 時点で 読み 500 万行／日・書き 10 万行／日・5 GB。「上限に当たるとクエリが実行できない」と公式にある（[D1 Pricing](https://developers.cloudflare.com/d1/platform/pricing/)）＝無料は無制限ではない。ライク 1 回は書き 1 行なので遠いが、上限に当たったときに画面がどうなるかは試していない。

D1 の無料枠は 2026-09-18 時点で 読み 500 万行／日・書き 10 万行／日・5 GB。「上限に当たるとクエリが実行できない」と公式にある（[D1 Pricing](https://developers.cloudflare.com/d1/platform/pricing/)）＝無料は無制限ではない。ライク 1 回は書き 1 行なので遠いが、上限に当たったときに画面がどうなるかは試していない。

### 加算は 1 文にした

`SELECT` して `UPDATE` する 2 段だと、同時に押されたときに読んだ値が古くなって取りこぼす。`INSERT … ON CONFLICT DO UPDATE … RETURNING` の **1 文**にして、読む・足す・返すを分けなかった。

仕様として言えるのは 2 つ。SQLite は「データベースに触るコマンドはトランザクションが無ければ自動で開始し、文が終わると自動でコミットする」（[SQLite: Transactions](https://www.sqlite.org/lang_transaction.html)）。D1 は「auto-commit で動作し、`batch()` の各文は順に非並行で実行・コミットされる」（[Cloudflare D1: D1 Database](https://developers.cloudflare.com/d1/worker-api/d1-database/)）。単一の `prepare().first()` の原子性を明示した文は、当方が読んだ範囲の公式には無かった。

実測として言えるのは 1 つ。ローカル（`wrangler pages dev`）で **並列 20 POST → 20**（取りこぼし 0）。GET 0 → POST 3 回で 1, 2, 3。「原子的だと証明した」ではなく「1 文にした＋並列 20 で 0」まで。

### 存在確認は POST だけ

`isLabSlug` は自分の静的ファイル `/lab/<slug>/` に HEAD を投げて、存在する記事だけ数える。目的は**ゴミ行を増やさない**こと（セキュリティ対策ではない）。GET は存在確認をせず、形式が正しい slug には `n: 0` を返す（本番で確認: 無い slug に GET → `{"ok":true,"n":0}`・POST → 404）。

### 画面側

```astro
<!-- Helpful.astro（記事末尾）: GET が ok のときだけ表示。JS 無し・503 なら何も出ない -->
```

押すと POST → 数字を 1 つ増やしてボタンを無効化・`localStorage['helpful:<slug>'] = '1'`。再読込後も無効のまま。重複防止はここだけ（サーバーは何も覚えない）。

## 結線でつまずいたところ

D1 の作成と `CREATE TABLE` はダッシュボードの Console で通った。Pages → Settings → Functions → D1 bindings の追加は、当方の環境ではダッシュボードの窓が小さく D1 の一覧が画面外に出て、**3 回とも保存されなかった**（保存後も一覧に出ず・API は 503 のまま）。`wrangler.toml` に書いて push したら通った。

```toml
[[d1_databases]]
binding = "LIKES"
database_name = "sumitsuke-likes"
database_id = "…"
```

ダッシュボードも `wrangler.toml` も正式な経路。当方の画面で前者が通らなかった、という観測。秘密（API キー）はダッシュボードのまま・`vars` だけを toml に写した。

## 本番 E2E

結線後に本番で 押す → 1 → 再読込でも無効 → 再 click でも 1（二重送信なし）まで確認し、テストの 1 票は DELETE した。手順と応答の全文は Lab 版に。

## 言わないこと

- 「水増しに耐える」とは言わない。localStorage を消せば再投票できる。対象外と決めた。
- 「原子的」を仕様として断言しない。1 文にした＋ローカル並列 20 で 0、まで。
- ライク数は実績にも営業にも使わない（privacy に明記）。だから守らなくてよい。
- コメント機能（Giscus 等）は入れていない。外部で技術的な補足や再現報告が 30 日で目安 5 件出たら再訪する、とだけ決めた。

本番 E2E の全文・数値・検証の記録（型）は本家 Sumitsuke Lab → [静的サイトに「役に立った」を追加の SaaS 無しで最小に付けられるか（検証の記録つき）](https://sumitsuke.jp/via/zenn/lab/helpful-button-d1-minimal/)。

### AI の利用について

Functions と画面のコードは AI（Claude Code）が書き、守る／守らないの裁定・結線の操作・公開の判断は人が行いました。対象は自社サイトで、顧客案件は含みません。

### 関連

D1 の速さ（cold／warm）を測った話は [無料枠サーバレス DB 3 種の cold/warm 実測](https://sumitsuke.jp/via/zenn/lab/serverless-db-cold-warm/)（速度の話。本記事は設計の話）。

次に読む: [検査器が見ている範囲と見ていない範囲を先に決める](https://sumitsuke.jp/via/zenn/lab/green-is-not-proof/)
