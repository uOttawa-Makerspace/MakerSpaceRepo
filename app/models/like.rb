# frozen_string_literal: true

class Like < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :repository, optional: true

  validates :repository_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  before_create { repository.increment!(:like) }

  before_destroy { repository.decrement!(:like) }
end
