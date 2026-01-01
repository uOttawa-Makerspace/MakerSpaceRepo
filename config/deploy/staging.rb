# frozen_string_literal: true

role :app, %w[deploy@staging-server.makerepo.com]
role :web, %w[deploy@staging-server.makerepo.com]
role :db, %w[deploy@staging-server.makerepo.com]

set :branch, "staging"
set :deploy_to, "/var/www/makerrepo-staging"
set :keep_releases, 3
# version is read from .ruby-version
set :maintenance_template_path,
    File.expand_path("../../maintenance/maintenance.html.erb", __FILE__)
