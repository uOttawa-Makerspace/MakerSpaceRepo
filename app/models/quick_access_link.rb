class QuickAccessLink < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :path, presence: true
  validates :path,
            uniqueness: {
              scope: :user_id,
              message: "You already have a quick access link to that location"
            }

  validate :path_must_be_valid

  def path_must_be_valid
    # this throws an exception on fail
    Rails.application.routes.recognize_path(path, method: :get)
  rescue ActionController::RoutingError
    errors.add(:path, "Path must be a valid path")
  end
end
