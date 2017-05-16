require 'test_helper'

class UpvoteTest < ActiveSupport::TestCase

	test "Comment ID uniqueness" do 
		upvote = Upvote.new(:user_id => 123123 , :comment_id => 456456)
		assert upvote.invalid? , "You have already upvoted this comment"

		upvote = Upvote.new(:user_id => 123123 , :comment_id => 654654)
		assert upvote.valid? , "You have already upvoted this comment"
	end

	test "User ID uniqueness" do

		upvote = Upvote.new(:user_id => 123123 , :comment_id => 456456)
		assert upvote.invalid? , "You have already upvoted this comment"

		upvote = Upvote.new(:user_id => 321321 , :comment_id => 456456)
		assert upvote.valid? , "You have already upvoted this comment"
	end

end
