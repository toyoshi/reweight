# frozen_string_literal: true

require "openai"

module Reweight
  class ProgressJudge
    SCREENING_PROMPT = <<~PROMPT
      あなたは「元気がでるニュース」を判定する専門家です。
      以下の記事タイトル一覧から、「読んだ人が元気になれる事例」に該当する可能性が高い記事の番号を選んでください。

      ## 採用条件
      - 問題が解決に向かっている
      - 数値的な改善が確認できる
      - 再現性のある取り組みである
      - 社会的な進展がある

      ## 不採用条件
      - 単なる感動話・美談
      - 不幸の裏返し構造
      - 扇情的なタイトル
      - 根拠不明の楽観論
      - 事件・事故・訃報・スポーツ結果

      候補になりそうな記事の番号をJSON配列で返してください。最大30件まで。
      例: {"candidates": [1, 5, 12, 23]}
    PROMPT

    BATCH_SCORING_PROMPT = <<~PROMPT
      あなたは「元気がでるニュース」を判定・要約する専門家です。
      複数のニュース記事について、それぞれ「読んだ人が元気になれる事例」に該当するかを判定し、同時に要約を作成してください。

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

      ## 要約ルール
      - 本文の転載はせず、独自の表現で要約する
      - 2〜3文程度で簡潔にまとめる
      - 「元気がでる」という観点を意識する
      - 事実ベースで、扇情的な表現は避ける

      各記事について、スコア(0〜100)・判定理由(1文)・要約(2〜3文)をJSON形式で返してください:
      {"results": [{"index": 1, "score": 85, "reason": "判定理由", "summary": "要約文"}, ...]}
    PROMPT

    BATCH_SIZE = 10

    def initialize
      @client = OpenAI::Client.new(access_token: Config.openai_api_key)
    end

    def judge_all(articles)
      # Step 1: バッチスクリーニング（gpt-4o-miniで候補を絞る）
      candidates = screen(articles)
      puts "Screening: #{articles.size} -> #{candidates.size} candidates"
      puts ""

      # Step 2: バッチスコアリング+要約（10件ずつまとめて処理）
      score_and_summarize_batch(candidates)

      # スクリーニングで落ちた記事はスコア0のまま
      articles
    end

    def select_top(articles, count: 3)
      articles.sort_by { |a| -a.progress_score }.first(count)
    end

    private

    def screen(articles)
      title_list = articles.each_with_index.map { |a, i| "#{i + 1}. #{a.title}" }.join("\n")

      response = @client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            { role: "system", content: SCREENING_PROMPT },
            { role: "user", content: title_list }
          ],
          temperature: 0.3,
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")
      result = JSON.parse(content)
      indices = result["candidates"] || []

      indices.filter_map { |i| articles[i - 1] if i >= 1 && i <= articles.size }
    rescue => e
      warn "[ERROR] Screening failed: #{e.message}"
      warn "Falling back to scoring all articles..."
      articles
    end

    def score_and_summarize_batch(candidates)
      candidates.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
        puts "Batch #{batch_idx + 1} (#{batch.size} articles):"
        process_batch(batch)
        batch.each do |article|
          puts "  #{article.progress_score}pt - #{article.title}"
        end
        puts ""
      end
    end

    def process_batch(batch)
      articles_text = batch.each_with_index.map do |article, i|
        "#{i + 1}. タイトル: #{article.title}\n   概要: #{article.summary}\n   出典: #{article.source}"
      end.join("\n\n")

      response = @client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            { role: "system", content: BATCH_SCORING_PROMPT },
            { role: "user", content: articles_text }
          ],
          temperature: 0.3,
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")
      result = JSON.parse(content)
      results = result["results"] || []

      results.each do |r|
        idx = r["index"].to_i - 1
        next if idx < 0 || idx >= batch.size

        batch[idx].progress_score = r["score"].to_i
        batch[idx].progress_reason = r["reason"].to_s
        batch[idx].ai_summary = r["summary"].to_s if r["summary"].to_s != ""
      end
    rescue => e
      warn "  [ERROR] Batch scoring failed: #{e.message}"
      batch.each do |article|
        article.progress_score = 0
        article.progress_reason = "判定エラー"
      end
    end
  end
end
