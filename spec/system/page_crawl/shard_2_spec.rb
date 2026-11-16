# frozen_string_literal: true

require "rails_helper"

# One fifth of the browser page crawl; see spec/support/page_crawl_browser.rb.
RSpec.describe "Page crawl (browser), shard 2 of 5", type: :system do
  it_behaves_like "a browser page crawl shard", 1
end
