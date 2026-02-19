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

    def self.mailerlite_api_token
      token = ENV["MAILERLITE_API_TOKEN"]
      (token.nil? || token.empty?) ? nil : token
    end

    def self.mailerlite_group_id
      gid = ENV["MAILERLITE_GROUP_ID"]
      (gid.nil? || gid.empty?) ? nil : gid
    end
  end
end
