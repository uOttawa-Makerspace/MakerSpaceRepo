# frozen_string_literal: true

class Like < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :repository, -> { including_hidden }, optional: true

  validates :repository_id, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  # Gives the like and counts it on the repository in the same transaction. False when the user already liked the
  # repository: a repeated click, or two simultaneous requests of which the unique index lets only one through.
  # Nothing is counted in that case.
  def self.give(repository, user)
    transaction do
      repository.likes.build(user_id: user.id).save && Repository.update_counters(repository.id, like: 1).positive?
    end
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Takes the like back. False when there is none (already taken back by a simultaneous request): the row is
  # locked first, so of two requests only one removes it and counts it.
  def self.take_back(repository, user)
    transaction do
      like = repository.likes.lock.find_by(user_id: user.id)
      like.present? && like.destroy.present? && Repository.update_counters(repository.id, like: -1).positive?
    end
  end
end
