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
    details = Rails.application.routes.recognize_path(path, method: :get)
    errors.add(:path, "cannot point to a user") if details[:controller] == 'users' && details[:action] == 'show'
  rescue ActionController::RoutingError
    # This error depends on the user route constraint being present, because any
    # top-level route can be a username.
    errors.add(:path, "must be a valid path")
  end
end
