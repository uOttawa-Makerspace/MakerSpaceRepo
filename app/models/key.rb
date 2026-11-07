class Key < ApplicationRecord
  # Raised when an assign or revoke is asked of a key in the wrong state.
  class StateError < StandardError
  end

  belongs_to :user, class_name: "User", optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  # belongs_to :key_request, optional: true
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

  def key_request
    user&.key_request
  end

  # Hands the key to a holder: saves the key as held and records the deposit
  # transaction in one database transaction, so a failure changes nothing.
  def assign_to!(user, attributes, deposit_amount)
    raise StateError, "Only a key in inventory can be assigned." unless status_inventory?

    transaction do
      update!(attributes.merge(user_id: user.id, status: :held))
      key_transactions.create!(user_id: user.id, deposit_amount: deposit_amount)
    end
  end

  # Takes the key back: returns it to inventory and closes its open transaction
  # in one database transaction. A held key with no open transaction is refused.
  def revoke!(deposit_return_date = nil)
    raise StateError, "Only a held key can be revoked." unless status_held?

    open_transaction = key_transactions.not_returned.order(created_at: :desc, id: :desc).first
    raise StateError, "This key has no open transaction to close." if open_transaction.nil?

    transaction do
      update!(user_id: nil, status: :inventory)
      open_transaction.close!(deposit_return_date)
    end
  end

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
