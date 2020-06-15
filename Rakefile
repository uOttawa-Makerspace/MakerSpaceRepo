# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative 'config/application'

# temp fix for NoMethodError: undefined method `last_comment'
module TempFixForRakeLastComment
  def last_comment
    last_description
  end
end
Rake::Application.include TempFixForRakeLastComment

Rails.application.load_tasks
