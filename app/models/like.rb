# frozen_string_literal: true

class Like < ApplicationRecord
  belongs_to :user
  belongs_to :repository

  validates :repository_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  before_create { repository.increment!(:like) }

  before_destroy { repository.decrement!(:like) }
end
