# frozen_string_literal: true

# Load DSL and set up stages
require 'capistrano/setup'

# Include default deployment tasks
require 'capistrano/deploy'
require 'capistrano/scm/git'

# Include tasks from other gems included in your Gemfile
require 'capistrano/rbenv' # include rbenv before puma
require 'capistrano/rails'
require 'capistrano/puma'
require 'whenever/capistrano'
require 'capistrano/maintenance'

install_plugin Capistrano::SCM::Git
install_plugin Capistrano::Puma
install_plugin Capistrano::Puma::Systemd

# Load custom tasks from `lib/capistrano/tasks' if you have any defined
Dir.glob('lib/capistrano/tasks/*.rake').each { |r| import r }
