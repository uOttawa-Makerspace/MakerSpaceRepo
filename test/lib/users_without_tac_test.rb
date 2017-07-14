# test/lib/users_without_tac.rb
require 'test_helper'
require 'rake'
load File.join(Rails.root, 'lib', 'tasks', 'users_without_tac.rake')

class UsersWithoutTacTest < ActiveSupport::TestCase
  setup do
    MakerSpaceRepo::Application.load_tasks
    Rake::Task['users_without_tac:get_users'].invoke
  end

  test "Only Sara is caught" do
      #I dont know how to test this
  end

end
