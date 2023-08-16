class Key < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  belongs_to :key_request, optional: true
  has_many :key_transactions, dependent: :destroy

  enum :status, %i[unknown inventory held lost], prefix: true
  enum :key_type, %i[regular sub_master keycard], prefix: true

  validates :user,
            presence: {
              message: "A user is required if the key is held"
            },
            if: :status_held?
  validates :supervisor,
            presence: {
              message: "A supervisor is required if the key is held"
            },
            if: :status_held?
  validates :space,
            presence: {
              message: "A space is required"
            },
            if: :key_type_regular?

  validates :number,
            presence: {
              message: "A key number is required"
            },
            uniqueness: {
              message: "A key already has that number"
            }

  validates :keycode, presence: { message: "A keycode is required" }
end
