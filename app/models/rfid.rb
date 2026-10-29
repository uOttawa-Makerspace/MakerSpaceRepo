class Rfid < ApplicationRecord
  belongs_to :user, optional: true
  scope :recent_unset, -> { where(user: nil).order("updated_at desc") }
  validates :card_number,
            presence: {
              message: "Card number is required."
            },
            uniqueness: {
              message: "Card number is already in use."
            }

  # Nothing defines a card number format (readers store whatever string they
  # send, unnormalised), so this is a sanity bound shared by the phone endpoints:
  # valid encoding, non-blank, at most 64 chars, no control characters.
  MAX_CARD_NUMBER_LENGTH = 64

  def self.valid_card_number?(card)
    card.is_a?(String) && card.valid_encoding? && card.strip.present? &&
      card.length <= MAX_CARD_NUMBER_LENGTH && !card.match?(/[[:cntrl:]]/)
  end

  # Links the card to the user, creating the card when no reader ever saw it
  # (phone-scanned: mac_address nil, which a reader tap would also leave for a
  # phone). Returns nil on success (also when already linked to this user) or the
  # refusal message, changing nothing. Lock order: user, then the card number
  # (rfids.card_number has no unique index, D-I46, so two requests creating the
  # same new card are serialised by a transaction advisory lock), then the card.
  def self.link_to_user!(card_number, user)
    transaction do
      User.where(id: user.id).lock("FOR NO KEY UPDATE").take
      lock_card_number(card_number)
      rfid = lock("FOR NO KEY UPDATE").find_by(card_number: card_number)
      if rfid&.user_id == user.id
        nil
      elsif rfid&.user_id.present?
        "is already linked to another user"
      elsif where(user_id: user.id).exists?
        "user already has a card; unlink it first"
      elsif rfid
        rfid.update!(user_id: user.id)
        nil
      else
        insert_card(card_number, user)
        nil
      end
    end
  end

  def self.lock_card_number(card_number)
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote("rfid:#{card_number}")}, 0))")
  end
  private_class_method :lock_card_number

  def self.insert_card(card_number, user)
    create!(card_number: card_number, mac_address: nil, user_id: user.id)
  end
  private_class_method :insert_card
end
