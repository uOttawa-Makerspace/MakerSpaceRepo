require 'test_helper'

class CommentTest < ActiveSupport::TestCase

	test "Presence of content" do 
		comment = comments(:one)

		comment.content = nil
		assert comment.invalid? , "Please add content"

		comment.content = "Great job!"
		assert comment.valid? , "Please add content"
	end

	test "Presence of user ID" do 
		comment = comments(:one)

		comment.user_id = nil
		assert comment.invalid? , "Please add user ID"

		comment.user_id = 246813579
		assert comment.valid? , "Please add user ID"
	end

	test "Presence of repository ID" do 
		comment = comments(:one)

		comment.repository_id = nil
		assert comment.invalid? , "Please add repositoy ID"

		comment.repository_id = 224466
		assert comment.valid? , "Please add repositoy ID"
	end

end
