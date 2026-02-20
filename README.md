# Reweight

RSSフィードから「おだやかニュース」をAIが選び、メールで届けるニュースレター。

## 必要なもの

- Ruby 3.3+
- OpenAI API キー
- MailerLite API トークン（メール配信用）

## セットアップ

```bash
cp .env.example .env
# .env に API キーを設定

bundle install
```

## 使い方

```bash
# ニュースレター生成
bundle exec ruby bin/generate

# メール配信
bundle exec ruby bin/send
```

`output/` ディレクトリにMarkdown形式のニュースレターが出力される。
`bin/send` はMailerLite経由で購読者にメールを配信する。

## フィード設定

`config/feeds.yml` でRSSフィードの追加・削除ができる。
