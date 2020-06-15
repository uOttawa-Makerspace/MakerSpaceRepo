# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :repository
  has_many :upvotes, dependent: :destroy

  paginates_per 5

  validates :content, presence: true
  validates :user_id, presence: true
  validates :repository_id, presence: true
end
