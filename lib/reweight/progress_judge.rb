# frozen_string_literal: true

require "openai"

module Reweight
  class ProgressJudge
    SCREENING_PROMPT = <<~PROMPT
      あなたは「元気がでるニュース」を判定する専門家です。
      以下の記事タイトル一覧から、「読んだ人がワクワクして元気になれる記事」に該当する可能性が高い記事の番号を選んでください。
      対象読者は一般の人（子供も含む）です。専門家向けの地味な話題ではなく、誰が読んでも「すごい！」「面白い！」と感じる記事を選んでください。

      ## 高く評価する記事
      - 未来を感じる発明・新技術・科学の発見（新しい治療法、画期的な技術など）
      - スポーツの快挙・躍進（メダル獲得、記録更新、成長物語）
      - 子どもの活躍・子ども向けの素敵な取り組み（図書館、教育プロジェクトなど）
      - 知識やツールの無料公開・オープン化（講座の無償公開、便利な公共サービスなど）
      - 文化的にユニークで面白いエピソード（意外な交流、ユニークな挑戦など）
      - 季節の話題（花粉、桜、初雪など、生活に身近なフラットなニュース）
      - 読んで「すごい！」「面白い！」と声が出るような具体的な成果

      ## 不採用にする記事
      - 地味な経済統計（機械受注、住宅着工件数、○○％増など数字だけのニュース）
      - 行政・制度の事務的な変更（法令改正、定員緩和、予算案など）
      - 政治家の発言・政治的な動き・国会の話題
      - 裁判・判決・違憲判断
      - 戦争・紛争・軍事行動
      - 事件・事故・訃報・暴力的な内容
      - 性的な内容（子供も安心して読めるコンテンツにする）
      - 単なる感動話・美談・不幸の裏返し構造
      - 扇情的なタイトル
      - 根拠不明の楽観論

      候補になりそうな記事の番号をJSON配列で返してください。最大30件まで。
      例: {"candidates": [1, 5, 12, 23]}
    PROMPT

    BATCH_SCORING_PROMPT = <<~PROMPT
      あなたは「元気がでるニュース」を判定・要約する専門家です。
      複数のニュース記事について、一般の読者（子供も含む）が読んで「ワクワクする」「元気になる」かを判定し、同時に要約を作成してください。

      ## 高スコアにする記事（80点以上）
      - 未来を感じる発明・新技術・科学や医学の発見（新しい治療法、画期的な技術など）
      - スポーツの快挙・躍進（メダル獲得、記録更新、成長ストーリー、それを支えた人の話）
      - 子どもの活躍・子ども向けの素敵な取り組み（図書館設立、教育プロジェクトなど）
      - 知識やツールの無料公開・オープン化（講座の無償公開、便利な公共サービスの開始など）
      - 文化的にユニークで面白いエピソード（意外な国際交流、ユニークな挑戦など）
      - 季節の話題（花粉、桜、初雪など、生活に身近なフラットなニュース）
      - 読んで「すごい！」「面白い！」と声が出るような具体的な成果

      ## 低スコアにする記事（30点以下）
      - 地味な経済統計（機械受注○％増、住宅着工件数など、数字だけで一般人がワクワクしないもの）
      - 行政・制度の事務的な変更（法令改正、定員緩和、予算案、審議会の了承など）
      - 政治家の発言・政治的な駆け引き・国会の話題
      - 裁判・判決・違憲判断（社会正義の話であっても前向きな気持ちになりにくい）
      - 単なる感動話・美談・不幸の裏返し構造

      ## 0点にする記事（絶対に採用しない）
      - 戦争・紛争・軍事行動
      - 事件・事故・訃報・暴力的な内容
      - 性的な内容（子供も安心して読めるコンテンツにする）
      - 扇情的・ゴシップ的な記事

      ## スコアリングの判断基準
      「一般の人がこのニュースを読んで、思わず誰かに教えたくなるか？」を基準にしてください。
      専門家にしか意味がわからない進展や、数字を読み解かないと価値がわからないニュースは低スコアにしてください。

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
