# frozen_string_literal: true

require "date"

module Reweight
  class EmailComposer
    OUTPUT_DIR = File.expand_path("../../output", __dir__)

    def initialize(articles, date: Date.today)
      @articles = articles
      @date = date
    end

    def compose
      lines = []
      lines << "# Reweight - #{@date.strftime('%Y-%m-%d')}"
      lines << ""
      lines << "今日の「前進」ニュース3選"
      lines << ""

      @articles.each_with_index do |article, i|
        lines << "---"
        lines << ""
        lines << "## #{i + 1}. #{article.title}"
        lines << ""
        lines << article.ai_summary
        lines << ""
        lines << "出典: [#{article.source}](#{article.url})"
        lines << ""
      end

      lines << "---"
      lines << ""
      lines << "*Reweight — 情報重み付けの再設計*"
      lines << ""

      lines.join("\n")
    end

    def save
      content = compose
      path = File.join(OUTPUT_DIR, "#{@date.strftime('%Y-%m-%d')}.md")
      File.write(path, content)
      puts "Saved: #{path}"
      path
    end
  end
end
