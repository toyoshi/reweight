# frozen_string_literal: true

require "yaml"

module Reweight
  class Config
    FEEDS_PATH = File.expand_path("../../config/feeds.yml", __dir__)

    def self.feeds
      data = YAML.load_file(FEEDS_PATH)
      data["feeds"]
    end

    def self.openai_api_key
      key = ENV["OPENAI_API_KEY"]
      raise "OPENAI_API_KEY is not set. Create a .env file based on .env.example" if key.nil? || key.empty?
      key
    end
  end
end
