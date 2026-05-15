# frozen_string_literal: true

source "https://rubygems.org"
ruby "4.0.2"
gem "rails", "~> 8.1"

# no longer standard since 3.4
gem "abbrev"
gem "csv"

gem "sitemap_generator", "~> 6.3"
gem "airbrake"
gem "bootsnap", require: false
gem "aws-sdk-s3", require: false
gem "bcrypt", "~> 3.1"
gem "caxlsx", "~> 4.0"
gem "chartkick"
gem "clipboard-rails"
gem "concurrent-ruby", "~> 1.1", ">= 1.1.6"
gem "excon"
gem 'fastimage', '~> 2.4'
gem "file_validators"
gem "font-awesome-rails", "~> 4.7.0.9"
gem "google-api-client", "~> 0.53.0", require: ["google/apis/calendar_v3"]
gem "googleauth"
gem "graphlient"
gem "groupdate"
gem 'icalendar'
gem "image_processing"
gem "jbuilder"
gem "kaminari"
gem "mocha"
gem "net-ssh"
gem "nobspw_rails7"
gem "octokit", '~> 10.0'
gem "pg", "~> 1.6"
gem "prettier_print"
gem "pry", "~> 0.15"
gem "pry-rails", "~> 0.3", group: :development
gem "psych", "~> 5.0"
gem "quick_random_records", "~> 0.3.2"
gem "rack-cors"
gem "roo", "~> 3.0"
gem "roo-xls"
gem 'rrule'
gem "rubyzip", "~> 3.0", require: "zip"
gem "saml_idp", "~> 1.0"
gem "sass-rails", "~> 6.0.0"
gem "sdoc", "~> 2.6", group: :doc
gem "shopify_app", "~> 23.0"
gem "simplecov", "~> 0.22"
gem "sprockets-rails"
gem "stimulus-rails"
gem "stripe"
gem "stripe_event", "~> 2.3", ">= 2.3.1"
gem "syntax_tree"
gem "syntax_tree-haml"
gem "syntax_tree-rbs"
gem 'terser', '~> 1.2'
gem "toastr-rails"
gem "trix-rails", "~> 2.4", require: "trix"
gem "vite_rails"
gem "whenever", require: false
gem "will_paginate", "~> 4.0"
gem "will_paginate-bootstrap-style"
gem "youtube_id"
gem "solid_queue", "~> 1.2"
gem "solid_cable"
gem "mission_control-jobs"

gem "puma", '~> 7.1'
gem 'redcarpet'

group :development, :test do
  gem 'rspec_junit_formatter'
  gem "byebug", platform: :mri
  gem "factory_bot_rails"
  gem "faker", "~> 3.1"
  gem "listen", "~> 3.7"
  gem "railroady"
  gem "rspec-json_expectations"
  gem "rspec-rails", "~> 8.0"
  gem "spring", "~> 4.4"
  gem "spring-watcher-listen", "~> 2.1.0"
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'ruby_audit', require: false
  gem 'rails_best_practices', require: false
  gem 'bullet'
  gem "faraday-retry", "~> 2.4"
end

group :development do
  # Capistrano deployment stuff
  gem "capistrano", "~> 3.10", require: false
  gem "capistrano-bundler", require: false
  gem "capistrano-maintenance", require: false
  gem "capistrano3-puma", require: false
  gem "capistrano-rails", require: false
  gem "capistrano-rbenv", require: false
  gem "erb_lint", require: false
  gem "letter_opener"
  gem "rubocop-rails"
  gem "web-console"
  gem "ruby-prof"

  gem "solargraph", require: false
  gem "solargraph-rails", require: false

  # ssh deployment
  gem "bcrypt_pbkdf", "~> 1.0"
  gem "ed25519", "~> 1.2"
end

group :test do
  gem 'test-prof'
  gem "capybara"
  gem "database_cleaner-active_record"
  gem "launchy", "~> 3.0"
  gem "rails-controller-testing"
  gem "rspec-retry"
  gem "selenium-webdriver", "~> 4.0"
  gem "shoulda-matchers", "~> 7.0"
end