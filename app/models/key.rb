class Key < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  belongs_to :key_request, optional: true
  has_many :key_transactions, dependent: :destroy

  enum :status,
       %i[unknown inventory held lost broken unrecoverable],
       prefix: true
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
  # validates :key_request,
  #           presence: {
  #             message: "A key request is required"
  #           },
  #           if: :status_held?

  validates :number,
            presence: {
              message: "A key number is required"
            },
            uniqueness: {
              scope: :space_id,
              message: "A key already has that number"
            },
            unless: -> { space.nil? }

  validates :number,
            presence: {
              message: "A key number is required"
            },
            uniqueness: {
              scope: :key_type,
              message: "A key already has that number"
            },
            unless: :key_type_regular?

  validates :custom_keycode,
            presence: {
              message: "A keycode is required"
            },
            unless: :key_type_regular?

  def get_latest_key_transaction
    KeyTransaction.where(key_id: id).order(created_at: :desc).first
  end

  def get_all_key_transactions
    KeyTransaction.where(key_id: id).order(created_at: :desc)
  end

  def get_keycode
    key_type_regular? ? space.keycode : custom_keycode
  end
end
