class Key < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true

  validates :user, presence: { message: "A user is required" }
  validates :supervisor, presence: { message: "A supervisor is required" }
  validates :space, presence: { message: "A space is required" }
  validates :number, presence: { message: "A key number is required" }
end
