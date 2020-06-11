# frozen_string_literal: true

class AddDownvoteToUpvotes < ActiveRecord::Migration
  def change
    add_column :upvotes, :downvote, :boolean
  end
end
