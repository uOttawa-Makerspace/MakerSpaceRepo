class AddDownvoteToUpvotes < ActiveRecord::Migration
  def change
    add_column :upvotes, :downvote, :boolean
  end
end
