class Key < ApplicationRecord
  belongs_to :holder, polymorphic: true, optional: true
  belongs_to :supervisor, class_name: "User", optional: true
  belongs_to :space, optional: true
  has_many :key_transactions, dependent: :destroy

  def user
    holder if holder_type == 'User'
  end

  def user_id
    holder_id if holder_type == 'User'
  end

  def user_id=(id)
    self.holder = id.present? ? User.find_by(id: id) : nil
  end

  enum :status, %i[unknown inventory held lost broken unrecoverable], prefix: true
  enum :key_type, %i[regular sub_master keycard], prefix: true

  validates :holder,
            presence: { message: "A holder is required if the key is held" },
            if: :status_held?

  validates :supervisor,
            presence: { message: "A supervisor is required if the key is held" },
            if: :status_held?

  validates :space,
            presence: { message: "A space is required" },
            if: :key_type_regular?

  validates :number,
            presence: { message: "A key number is required" },
            uniqueness: { scope: :space_id, message: "A key already has that number" },
            unless: -> { space.nil? }

  validates :number,
            presence: { message: "A key number is required" },
            uniqueness: { scope: :key_type, message: "A key already has that number" },
            unless: :key_type_regular?

  validates :custom_keycode,
            presence: { message: "A keycode is required" },
            unless: :key_type_regular?

  def key_request
    user&.key_request
  end

  def get_latest_key_transaction
    key_transactions.order(created_at: :desc).first
  end

  def get_all_key_transactions
    key_transactions.order(created_at: :desc)
  end

  def get_keycode
    key_type_regular? ? space.keycode : custom_keycode
  end

  def assignee_name
    holder&.name || 'Unassigned'
  end

  def assignee_email
    holder.try(:email)
  end
end