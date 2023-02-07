# frozen_string_literal: true

source "https://rubygems.org"
ruby "2.7.3"
gem "rails", "~> 6.1.4.1"

gem "webpacker"
gem "aws-sdk", "~> 3.0.1"
gem "aws-sdk-s3", require: false
gem "bcrypt", "~> 3.1.10"
gem "bootbox-rails", "~>0.4"
# gem 'bootstrap', '~> 4.5.0'
# gem 'bootstrap-sass'
gem "caxlsx", "~> 3.0.1"
gem "clipboard-rails"
gem "coffee-rails", "5.0.0"
gem "excon"
gem "fastimage", "~> 1.7.0"
gem "font-awesome-rails", "~> 4.7.0.7"
gem "jbuilder"
gem "jquery-rails"
gem "jquery-ui-rails"
gem "kaminari"
gem "mocha"
gem "octokit", "~> 4.21.0"
gem "paperclip"
gem "paperclip-av-transcoder"
gem "pg", "~> 1.1"
# gem 'photoswipe-rails', '~> 4.0.8a'
gem "progress_bar", "~> 1.0.3"
gem "pry", "~> 0.10.4"
gem "pry-rails", "~> 0.3.9", group: :development
gem "quick_random_records", "~> 0.3.2"
gem "rubyzip", "~> 2.1", require: "zip"
gem "saml_idp", "~> 0.9.0"
gem "sass-rails", "~> 6.0.0"
gem "sdoc", "~> 1.1.0", group: :doc
gem "shopify_app", "~> 18.1.2"
gem "sidekiq", "~> 6.4.0"
gem "simplecov"
gem "thin", "~> 1.8.1"
gem "toastr-rails"
gem "turbolinks", "~> 5.2.0"
gem "uglifier", ">= 1.3.0"
gem "unicorn-worker-killer", "~> 0.4.3"
gem "whenever", require: false
gem "wicked_pdf"
gem "will_paginate", "~> 3.3.0"
gem "will_paginate-bootstrap-style"
gem "wkhtmltopdf-binary"
gem "youtube_id"
gem "bootsnap", require: false
# gem 'actiontext', github: 'kobaltz/actiontext', branch: 'archive', require: 'action_text'
gem "image_processing"
gem "file_validators"
gem "trix-rails", "~> 2.3.0", require: "trix"
gem "zip-zip"
gem "concurrent-ruby", "~> 1.1", ">= 1.1.6"
gem "net-ssh"
gem "roo", "~> 2.8.3"
gem "roo-xls"
gem "googleauth", "~> 0.15.0"
gem "google-api-client", require: ["google/apis/calendar_v3"]
gem "faraday", "~> 0.17.0"
gem "recaptcha"
gem "rack-cors"
gem "stripe_event", "~> 2.3", ">= 2.3.1"
gem "stripe"
gem "airbrake"
gem "prettier_print"
gem "syntax_tree", "~> 3.3.0"
gem "syntax_tree-haml"
gem "syntax_tree-rbs"
gem "stimulus-rails"
gem "graphlient"

group :development, :test do
  gem "byebug", platform: :mri
  gem "rspec-rails", "~> 5.0.0"
  gem "rspec-json_expectations"
  gem "faker", "~> 2.0.0"
  gem "railroady"
  gem "factory_bot_rails"
  gem "spring", "~> 2.1.0"
  gem "listen", "~> 3.2.1"
  gem "spring-watcher-listen", "~> 2.0.0"
end

group :development do
  # Capistrano deployment stuff
  gem "capistrano", "~> 3.10", require: false
  gem "capistrano-rails", "~> 1.6", require: false
  gem "capistrano-bundler"
  gem "capistrano-passenger", ">= 0.2.1"
  gem "capistrano-rbenv", "~> 2.1"
  gem "capistrano-maintenance", "~> 1.2", require: false
  gem "letter_opener" # Open emails in development
  gem "rubocop-rails"
  gem "web-console"
  gem "erb_lint", require: false

  # ssh deploymentque
  gem "bcrypt_pbkdf", "~> 1.0"
  gem "ed25519", "~> 1.2"
end

group :test do
  gem "capybara"
  gem "database_cleaner-active_record"
  gem "launchy", "~> 2.2"
  gem "rails-controller-testing"
  gem "selenium-webdriver", "~> 3.142.7"
  gem "shoulda-matchers", "~> 4.0"
end
