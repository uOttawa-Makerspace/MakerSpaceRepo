class Key < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  has_many_attached :files, dependent: :destroy

  enum :status, %i[unknown inventory held lost]

  validates :user, presence: { message: "A user is required" }
  validates :supervisor, presence: { message: "A supervisor is required" }
  validates :space, presence: { message: "A space is required" }
  validates :number,
            presence: {
              message: "A key number is required"
            },
            uniqueness: {
              message: "A key already has that number"
            }

  validates :files,
            file_content_type: {
              allow: %w[application/pdf],
              if: -> { files.attached? }
            }

  scope :deposit_paid, -> { where.not(deposit_return_date: nil) }
  scope :deposit_not_paid, -> { where(deposit_return_date: nil) }
end
