# frozen_string_literal: true

source "https://rubygems.org"
ruby "4.0.6"

gem "rails", "~> 8.1"

# Standard libraries
gem "abbrev"
gem "csv"

# Core Application Gems
gem "airbrake"
gem "aws-sdk-s3", require: false
gem "bcrypt", "~> 3.1"
gem "bootsnap", require: false
gem "caxlsx", "~> 4.0"
gem "chartkick"
gem "concurrent-ruby", "~> 1.3", ">= 1.3.7"
gem "excon"
gem "fastimage", "~> 2.4"
gem "file_validators"
gem "google-apis-calendar_v3"
gem "googleauth"
gem "graphlient"
gem "groupdate"
gem "icalendar"
gem "image_processing"
gem "jbuilder"
gem "mission_control-jobs"
gem "multi_json"
gem "net-ssh"
gem "nobspw_rails7"
gem "octokit", "~> 10.0"
gem "pg", "~> 1.6"
gem "puma", "~> 7.2.1"
gem "psych", "~> 5.0"
gem "quick_random_records", "~> 0.3.2"
gem "rack-cors"
gem "redcarpet"
gem "roo", "~> 3.0"
gem "roo-xls"
gem "rrule"
gem "rubyzip", "~> 3.0", require: "zip"
gem "saml_idp", "~> 1.0"
gem "shopify_app", "~> 23.0"
gem "sitemap_generator", "~> 6.3"
gem "solid_cable"
gem "solid_queue", "~> 1.2"
gem "stimulus-rails"
gem "stripe"
gem "stripe_event", "~> 2.3", ">= 2.3.1"
gem "trix-rails", "~> 2.4", require: "trix"
gem "vite_rails"
gem "whenever", require: false
gem "youtube_id"
gem "ruby-vips", "~> 2.3.x"
gem 'pagy', '>= 43.6.1'
gem "propshaft"

group :development, :test do
  gem "brakeman", require: false
  gem "bullet"
  gem "bundler-audit", require: false
  gem "byebug", platform: :mri
  gem "factory_bot_rails"
  gem "faker", "~> 3.1"
  gem "faraday-retry", "~> 2.4"
  gem "listen", "~> 3.7"
  gem "mocha"
  gem "prettier_print"
  gem "pry", "~> 0.15"
  gem "pry-rails", "~> 0.3"
  gem "rails_best_practices", require: false
  gem "railroady"
  gem "rspec-json_expectations"
  gem "rspec-rails", "~> 8.0"
  gem "rspec_junit_formatter"
  gem "ruby_audit", require: false
  gem "simplecov", "~> 0.22"
  gem "spring", "~> 4.4"
  gem "spring-watcher-listen", "~> 2.1.0"
  gem "syntax_tree"
  gem "syntax_tree-haml"
  gem "syntax_tree-rbs"
end

group :development do
  gem "capistrano", "~> 3.10", require: false
  gem "capistrano-bundler", require: false
  gem "capistrano-maintenance", require: false
  gem "capistrano-rails", require: false
  gem "capistrano-rbenv", require: false
  gem "capistrano3-puma", require: false
  gem "erb_lint", require: false
  gem "letter_opener_web"
  gem "rubocop-rails"
  gem "ruby-prof"
  gem "sdoc", "~> 2.6"
  gem "solargraph", require: false
  gem "solargraph-rails", require: false
  gem "web-console"

  # SSH deployment
  gem "bcrypt_pbkdf", "~> 1.0"
  gem "ed25519", "~> 1.2"
end

group :test do
  gem "capybara"
  gem "database_cleaner-active_record"
  gem "launchy", "~> 3.0"
  gem "rails-controller-testing"
  gem "rspec-retry"
  gem "selenium-webdriver", "~> 4.0"
  gem "shoulda-matchers", "~> 7.0"
  gem "test-prof"
end