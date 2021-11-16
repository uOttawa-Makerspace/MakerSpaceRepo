# frozen_string_literal: true

role :app, %w[deploy@server.makerepo.com]
role :web, %w[deploy@server.makerepo.com]
role :db,  %w[deploy@server.makerepo.com]

set :branch, ENV['BRANCH'] if ENV['BRANCH']
set :deploy_to, '/var/www/makerrepo-dev'
set :keep_releases, 1
set :rbenv_ruby, '2.7.2'

