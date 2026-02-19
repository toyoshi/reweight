# frozen_string_literal: true

module Reweight
  class Article
    attr_accessor :title, :url, :summary, :source, :published_at
    attr_accessor :progress_score, :progress_reason, :ai_summary, :category

    def initialize(title:, url:, summary: "", source: "", published_at: nil)
      @title = title
      @url = url
      @summary = summary
      @source = source
      @published_at = published_at
      @progress_score = 0
      @progress_reason = ""
      @ai_summary = ""
      @category = ""
    end

    def to_s
      "[#{source}] #{title}"
    end
  end
end
