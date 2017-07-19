# test/lib/users_without_tac.rb
require 'test_helper'
require 'rake'

load File.join(Rails.root, 'lib', 'tasks', 'users_without_tac.rake')

class UsersWithoutTacTest < ActiveSupport::TestCase
  setup do
    @tasks = MakerSpaceRepo::Application.load_tasks
    @task = Rake::Task['users_without_tac:get_users'].invoke
  end

  test "Only Sara is caught" do
      assert $emails.include? "sara@sara.com"
  end

end
