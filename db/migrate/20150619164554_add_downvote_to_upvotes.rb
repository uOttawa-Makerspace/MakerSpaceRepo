# frozen_string_literal: true

class AddDownvoteToUpvotes < ActiveRecord::Migration[5.0]
  def change
    add_column :upvotes, :downvote, :boolean
  end
end
