class Rfid < ApplicationRecord
  # Raised by unlink_card! when the card's owner kept changing under it.
  class OwnerChanging < ActiveRecord::ActiveRecordError; end

  belongs_to :user, optional: true
  scope :recent_unset, -> { where(user: nil).order("updated_at desc") }
  # Uniqueness is the unique index's job (find_or_create_card handles the conflict).
  validates :card_number, presence: { message: "Card number is required." }

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
  # refusal message, changing nothing. Every change of a card's owner goes through
  # this or the unlink methods below. Lock order: user, then the card number, then
  # the card. The advisory lock on the card number serialises owner changes; it
  # does not serialise creating the row, which find_or_create_card does safely on
  # its own (a tap may create the same card meanwhile). The user's own card is
  # checked first and a row is only created once every refusal has been ruled out,
  # so a refused link never inserts anything.
  def self.link_to_user!(card_number, user)
    transaction do
      User.where(id: user.id).lock("FOR NO KEY UPDATE").take
      lock_card_number(card_number)
      held = where(user_id: user.id).take
      next if held&.card_number == card_number

      rfid = lock("FOR NO KEY UPDATE").find_by(card_number: card_number)
      if rfid&.user_id.present?
        "is already linked to another user"
      elsif held
        "user already has a card; unlink it first"
      else
        rfid, _created = find_or_create_card(card_number) unless rfid
        if rfid.persisted?
          rfid.lock!("FOR NO KEY UPDATE")
          rfid.update!(user_id: user.id)
          nil
        else
          "is invalid"
        end
      end
    end
  end

  # Unlinks every card the user holds (normally one) and re-homes it: its
  # mac_address becomes the first reader of the actor's assigned space (the space
  # the unlinked-card lists filter on), so the card shows up in the actor's list.
  # An actor without an assigned space, or whose space has no reader, leaves the
  # mac_address unchanged. Returns the number of cards unlinked (0 is a no-op).
  # Lock order matches link_to_user!: the user, then the cards.
  def self.unlink_from_user!(user, actor:)
    transaction do
      User.where(id: user.id).lock("FOR NO KEY UPDATE").take
      cards = where(user_id: user.id).lock("FOR NO KEY UPDATE").to_a
      reader = rehome_reader(actor)
      cards.each { |rfid| release_card!(rfid, reader) }
      cards.size
    end
  end

  # Unlinks exactly the card with this number and re-homes it as
  # unlink_from_user! does, leaving any other card its owner holds alone.
  # Returns :unlinked, :already_unlinked (nothing changed) or :not_found.
  # Lock order matches link_to_user!: the owner, then the card number, then the
  # card. The owner is only known from the card, so it is read first and
  # re-checked under the locks; if the card was linked to someone else meanwhile
  # the attempt starts over with the new owner.
  def self.unlink_card!(card_number, actor:)
    attempts = 0
    loop do
      attempts += 1
      outcome = transaction do
        owner_id = where(card_number: card_number).pick(:user_id)
        User.where(id: owner_id).lock("FOR NO KEY UPDATE").take if owner_id
        lock_card_number(card_number)
        rfid = lock("FOR NO KEY UPDATE").find_by(card_number: card_number)
        if rfid.nil?
          :not_found
        elsif rfid.user_id != owner_id
          :retry
        elsif rfid.user_id.nil?
          :already_unlinked
        else
          release_card!(rfid, rehome_reader(actor))
          :unlinked
        end
      end
      return outcome unless outcome == :retry
      raise OwnerChanging, "card kept changing owner" if attempts >= 5
    end
  end

  def self.rehome_reader(actor)
    actor.space&.pi_readers&.first
  end
  private_class_method :rehome_reader

  def self.release_card!(rfid, reader)
    rfid.user_id = nil
    rfid.mac_address = reader.pi_mac_address if reader
    rfid.save!
  end
  private_class_method :release_card!

  def self.lock_card_number(card_number)
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote("rfid:#{card_number}")}, 0))")
  end
  private_class_method :lock_card_number

  # The one way a card row is created (a tap of an unknown card, a staff link of
  # a card no reader saw). Returns [rfid, created]; created is true only for the
  # caller whose insert made the row. A blank or nil number is refused before any
  # query: the card comes back unsaved with its error. Safe when two requests
  # create the same number at once: the insert is INSERT ... ON CONFLICT
  # (card_number) DO NOTHING against the unique index, and whoever loses reads the
  # winner's row.
  def self.find_or_create_card(card_number, mac_address: nil)
    card = new(card_number: card_number, mac_address: mac_address)
    return [card, false] unless card.valid?

    existing = find_by(card_number: card_number)
    return [existing, false] if existing

    inserted = insert({ card_number: card_number, mac_address: mac_address },
                      unique_by: :card_number, returning: column_names)
    return [find_by!(card_number: card_number), false] if inserted.rows.empty?

    [instantiate(inserted.to_a.first), true]
  end
end
