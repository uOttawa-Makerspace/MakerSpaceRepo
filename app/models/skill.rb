class Skill < ApplicationRecord
  has_many :trainings
  has_many :learning_modules, through: :trainings
  before_destroy :remove_training_relation

  private

  def remove_training_relation
    self.trainings.update_all(skill_id: nil)
  end
end
