# frozen_string_literal: true

require "openai"

module Reweight
  class ProgressJudge
    SYSTEM_PROMPT = <<~PROMPT
      あなたは「世界の前進」を判定する専門家です。
      ニュース記事が「世界が一歩前に進んだ事例」に該当するかを判定してください。

      ## 採用条件（スコアを高くする）
      - 問題が解決に向かっている
      - 数値的な改善が確認できる
      - 再現性のある取り組みである
      - 社会的な進展がある

      ## 不採用条件（スコアを低くする）
      - 単なる感動話・美談
      - 不幸の裏返し構造（悲劇があったからこそ生まれた話）
      - 扇情的なタイトルに依存している
      - 根拠不明の楽観論

      回答はJSON形式で返してください:
      {"score": 0〜100の整数, "reason": "判定理由を1文で"}
    PROMPT

    def initialize
      @client = OpenAI::Client.new(access_token: Config.openai_api_key)
    end

    def judge(article)
      user_message = "記事タイトル: #{article.title}\n記事概要: #{article.summary}\n出典: #{article.source}"

      response = @client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: user_message }
          ],
          temperature: 0.3,
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")
      result = JSON.parse(content)

      article.progress_score = result["score"].to_i
      article.progress_reason = result["reason"].to_s
      article
    rescue => e
      warn "  [ERROR] Judge failed for '#{article.title}': #{e.message}"
      article.progress_score = 0
      article.progress_reason = "判定エラー"
      article
    end

    def judge_all(articles)
      articles.each_with_index do |article, i|
        puts "Judging (#{i + 1}/#{articles.size}): #{article.title}"
        judge(article)
        puts "  -> Score: #{article.progress_score} - #{article.progress_reason}"
      end
      articles
    end

    def select_top(articles, count: 3)
      articles.sort_by { |a| -a.progress_score }.first(count)
    end
  end
end
