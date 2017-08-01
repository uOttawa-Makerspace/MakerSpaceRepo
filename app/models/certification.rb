class Certification < ApplicationRecord
  belongs_to :user
  belongs_to :training_session

  validates :user, presence: true
  validates :training_session, presence: true

  def training
    return self.training_session.training.name
  end

  def trainer
    return self.training_session.user.name
  end

end
