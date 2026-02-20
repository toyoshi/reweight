# frozen_string_literal: true

require "openai"

module Reweight
  class ProgressJudge
    SCREENING_PROMPT = <<~PROMPT
      あなたは「おだやかニュース」を選ぶ専門家です。
      以下の記事タイトル一覧から、「読んだ人が穏やかな気持ちで読め、じんわり面白いと感じる記事」に該当する可能性が高い記事の番号を選んでください。
      対象読者は一般の人（子供も含む）です。

      ## 選ぶべき記事（低覚醒・ポジティブ）
      - 科学・医学のじっくりした進展（新しい治療法、地道な研究成果など）
      - 動物・自然のほのぼのした話題
      - 子ども向けの穏やかな取り組み（図書館設立、教育プロジェクトなど）
      - 知識やツールの無料公開・オープン化
      - 文化的にユニークで静かに面白いエピソード
      - 季節の話題（花粉、桜、初雪など、生活に身近なニュース）
      - 地域の穏やかな取り組みや工夫

      ## 選ばない記事
      - スポーツの勝敗・競争結果（メダル、優勝、記録更新など → 羨望・焦りを生む）
      - 競争やランキングを煽る内容
      - 地味な経済統計（数字だけのニュース）
      - 行政・制度の事務的な変更
      - 政治家の発言・政治的な動き
      - 裁判・判決
      - 戦争・紛争・軍事行動
      - 事件・事故・訃報・暴力的な内容
      - 性的な内容
      - 扇情的・ゴシップ的な記事
      - 感動の押し売り・美談・不幸の裏返し構造

      候補になりそうな記事の番号をJSON配列で返してください。最大30件まで。
      例: {"candidates": [1, 5, 12, 23]}
    PROMPT

    BATCH_SCORING_PROMPT = <<~PROMPT
      あなたは「おだやかニュース」を判定・要約する専門家です。
      複数のニュース記事について、一般の読者（子供も含む）が穏やかな気持ちで読めるかを判定し、同時に要約を作成してください。

      ## スコアリングの判断基準（2軸で判定）

      **軸1: 穏やかな知的満足を与えるか**
      読後に「へぇ」「なるほど」「なごむ」と静かに感じられる記事を高く評価する。
      興奮や高揚を誘う記事は低く評価する。

      **軸2: ネガティブ感情を誘発しないか**
      読後に嫉妬・怒り・悲しみ・焦り・羨望が浮かぶ記事は低く評価する。
      誰が読んでも心が波立たない記事を高く評価する。

      ## 高スコアにする記事（80点以上）
      - 科学・医学のじっくりした進展（新しい治療法、地道な研究成果など）
      - 動物・自然のほのぼのした話題
      - 子ども向けの穏やかな取り組み（図書館設立、教育プロジェクトなど）
      - 知識やツールの無料公開・オープン化
      - 文化的にユニークで静かに面白いエピソード
      - 季節の話題（花粉、桜、初雪など）
      - 地域の穏やかな取り組みや工夫

      ## 低スコアにする記事（30点以下）
      - スポーツの勝敗・競争結果（メダル、優勝、記録更新 → 羨望・焦りを生む）
      - 競争やランキングを煽る内容
      - 地味な経済統計（数字だけで一般人が興味を持ちにくいもの）
      - 行政・制度の事務的な変更
      - 政治家の発言・政治的な駆け引き
      - 裁判・判決
      - 感動の押し売り・美談・不幸の裏返し構造

      ## 0点にする記事（絶対に採用しない）
      - 戦争・紛争・軍事行動
      - 事件・事故・訃報・暴力的な内容
      - 性的な内容（子供も安心して読めるコンテンツにする）
      - 扇情的・ゴシップ的な記事

      ## 要約ルール
      - 本文の転載はせず、独自の表現で要約する
      - 2〜3文程度で簡潔にまとめる
      - 穏やかに読めるトーンを意識する
      - 事実ベースで、扇情的な表現は避ける

      ## カテゴリ分類
      各記事に短いカテゴリ名（5〜15文字）をつけてください。
      同じ出来事・話題を扱う記事には同じカテゴリ名をつけてください。
      例: 「iPS細胞臨床研究」「北大子ども図書館」「春の花粉情報」

      各記事について、スコア(0〜100)・判定理由(1文)・要約(2〜3文)・カテゴリをJSON形式で返してください:
      {"results": [{"index": 1, "score": 85, "reason": "判定理由", "summary": "要約文", "category": "カテゴリ名"}, ...]}
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

    def select_top(articles, count: 10)
      max_per_category = count / 2
      sorted = articles.sort_by { |a| -a.progress_score }
      selected = []
      category_counts = Hash.new(0)

      sorted.each do |article|
        break if selected.size >= count

        cat = article.category.to_s.strip
        if cat != "" && category_counts[cat] >= max_per_category
          puts "  [dedup] skipped (#{cat}): #{article.title}"
          next
        end

        selected << article
        category_counts[cat] += 1 if cat != ""
      end

      selected
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
        batch[idx].category = r["category"].to_s if r["category"].to_s != ""
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
