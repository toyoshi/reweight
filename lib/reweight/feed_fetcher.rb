# frozen_string_literal: true

require "feedjira"
require "open-uri"
require "set"

module Reweight
  class FeedFetcher
    def initialize(feeds: Config.feeds)
      @feeds = feeds
    end

    def fetch_all
      articles = []

      @feeds.each do |feed_config|
        name = feed_config["name"]
        url = feed_config["url"]

        puts "Fetching: #{name} (#{url})"
        fetched = fetch_feed(url, name)
        puts "  -> #{fetched.size} articles"
        articles.concat(fetched)
      rescue => e
        warn "  [ERROR] Failed to fetch #{name}: #{e.message}"
      end

      dedup(articles)
    end

    private

    def normalize_url(url)
      uri = URI.parse(url)
      uri.query = nil
      uri.fragment = nil
      path = uri.path.chomp("/")
      uri.path = path.empty? ? "/" : path
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def dedup(articles)
      seen = Set.new
      articles.select do |article|
        key = normalize_url(article.url)
        seen.add?(key)
      end
    end

    def fetch_feed(url, source_name)
      xml = URI.open(url, open_timeout: 10, read_timeout: 10).read
      feed = Feedjira.parse(xml)

      feed.entries.map do |entry|
        Article.new(
          title: entry.title&.strip || "",
          url: entry.url || entry.entry_id || "",
          summary: entry.summary&.strip || "",
          source: source_name,
          published_at: entry.published
        )
      end
    end
  end
end
