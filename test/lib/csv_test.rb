# test/lib/users_without_tac.rb
require 'test_helper'
require 'rake'

load File.join(Rails.root, 'lib', 'tasks', 'csv.rake')

class CsvTest < ActiveSupport::TestCase
  setup do
    @tasks = MakerSpaceRepo::Application.load_tasks
    @task = Rake::Task['csv:legible_users'].invoke
  end

  test "bob and olivia are users with a student_id and/or email in our database" do
      assert $legible_users.include? users(:bob)
      assert $legible_users.include? users(:olivia)
  end

end
