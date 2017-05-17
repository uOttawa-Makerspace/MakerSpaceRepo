require 'test_helper'

class UpvoteTest < ActiveSupport::TestCase

	test "Comment ID uniqueness" do
		user1 = users(:bob)
		user2 = users(:mary)

		upvote1 = Upvote.new(:user => user1 , :comment_id => 456456)
		upvote2 = Upvote.new(:user => user2 , :comment_id => 654654)

		assert_not_equal(upvote1.comment_id , upvote2.comment_id, "Comment ID's are not unique")

 
		upvote1 = Upvote.new(:user => user1 , :comment_id => 456456)
		upvote2 = Upvote.new(:user => user2 , :comment_id => 456456)

		assert_equal(upvote1.comment_id , upvote2.comment_id, "Comment ID's are unique")
	end


	test "User ID presence" do

		upvote = Upvote.new(:user => nil , :comment_id => 654654)
		assert upvote.invalid? , "Please provide user ID"

		upvote = Upvote.new(:user => users(:bob) , :comment_id => 654654)
		assert upvote.valid? , "Please provide user ID"
	end

end
