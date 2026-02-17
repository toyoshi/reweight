# Reweight

RSSフィードから元気がでるニュース記事をAIが選び、要約付きニュースレターを生成するCLIツール。

## 必要なもの

- Ruby 3.3+
- OpenAI API キー

## セットアップ

```bash
cp .env.example .env
# .env に OpenAI API キーを設定

bundle install
```

## 使い方

```bash
bundle exec ruby bin/generate
```

`output/` ディレクトリにMarkdown形式のニュースレターが出力される。

## フィード設定

`config/feeds.yml` でRSSフィードの追加・削除ができる。
