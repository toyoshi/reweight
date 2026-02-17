# frozen_string_literal: true

require "dotenv/load"

require_relative "reweight/config"
require_relative "reweight/article"
require_relative "reweight/feed_fetcher"
require_relative "reweight/progress_judge"
require_relative "reweight/summarizer"
require_relative "reweight/email_composer"

module Reweight
end
