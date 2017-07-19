require 'test_helper'

class RepositoryTest < ActiveSupport::TestCase

	test "Presence of title" do
		repository = repositories(:one)

		repository.title = "Project 1"
		assert repository.valid? , "Project title is required."

		repository.title = nil
		assert repository.invalid? , "Project title is required."
	end

	test "Uniqueness of repository title" do

		repository = repositories(:two)

		repository.title = "Repository1"
		repository.user_username = "bob"
		assert repository.invalid? , "Project title is already in use."


		repository.title = "Repository2"
		assert repository.valid? , "Project title is already in use."
	end

	test "Valid project title" do
		repository = repositories(:one)

		repository.title = "MakerRepo"
		assert repository.valid?, "Invalid project title"

		repository.title = "/*MakerRepo*/"
		assert repository.invalid?, "Invalid project title"

	end
end
