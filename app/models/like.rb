# frozen_string_literal: true

class Like < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :repository, optional: true

  validates :repository_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  # Gives the like. False when the user already liked the repository: a repeated click, or two simultaneous
  # requests of which the unique index lets only one through. Nothing is counted in that case.
  def self.give(repository, user)
    repository.likes.build(user_id: user.id).save
  rescue ActiveRecord::RecordNotUnique
    false
  end

  before_create { repository.increment!(:like) }

  before_destroy { repository.decrement!(:like) }
end
