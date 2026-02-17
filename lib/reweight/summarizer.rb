# frozen_string_literal: true

require "openai"

module Reweight
  class Summarizer
    SYSTEM_PROMPT = <<~PROMPT
      あなたはニュース要約の専門家です。
      与えられたニュース記事について、独自の要約文を日本語で作成してください。

      ルール:
      - 本文の転載はせず、独自の表現で要約する
      - 2〜3文程度で簡潔にまとめる
      - 「元気がでる」という観点を意識する
      - 事実ベースで、扇情的な表現は避ける
    PROMPT

    def initialize
      @client = OpenAI::Client.new(access_token: Config.openai_api_key)
    end

    def summarize(article)
      user_message = "記事タイトル: #{article.title}\n記事概要: #{article.summary}\n出典: #{article.source}"

      response = @client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: user_message }
          ],
          temperature: 0.5
        }
      )

      article.ai_summary = response.dig("choices", 0, "message", "content").to_s.strip
      article
    rescue => e
      warn "  [ERROR] Summarize failed for '#{article.title}': #{e.message}"
      article.ai_summary = article.summary
      article
    end

    def summarize_all(articles)
      articles.each_with_index do |article, i|
        puts "Summarizing (#{i + 1}/#{articles.size}): #{article.title}"
        summarize(article)
      end
      articles
    end
  end
end
