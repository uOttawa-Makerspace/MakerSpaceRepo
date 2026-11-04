class Rfid < ApplicationRecord
  # Raised by unlink_card! when the card's owner kept changing under it.
  class OwnerChanging < ActiveRecord::ActiveRecordError; end

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
  # refusal message, changing nothing. Lock order: user, then the card number,
  # then the card. The advisory lock on the card number serialises changes of a
  # card's owner (link and unlink); it does not serialise creating the row, which
  # find_or_create_card does safely on its own, so a tap that creates the same
  # card meanwhile is picked up and linked.
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
        rfid, created = find_or_create_card(card_number, user_id: user.id)
        rfid.update!(user_id: user.id) unless created
        nil
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
  # a card no reader saw). Safe when two requests create the same number at once:
  # the insert is INSERT ... ON CONFLICT (card_number) DO NOTHING against the unique
  # index, and whoever loses reads the winner's row. Returns [rfid, created]:
  # created is true only for the caller whose insert made the row. An invalid card
  # (a blank number) is returned unsaved with its errors and created false.
  def self.find_or_create_card(card_number, mac_address: nil, user_id: nil)
    existing = find_by(card_number: card_number)
    return [existing, false] if existing

    card = new(card_number: card_number, mac_address: mac_address, user_id: user_id)
    unless card.valid?
      winner = find_by(card_number: card_number) if card.errors.of_kind?(:card_number, :taken)
      return [winner || card, false]
    end

    inserted = insert({ card_number: card_number, mac_address: mac_address, user_id: user_id },
                      unique_by: :card_number, returning: :id)
    return [find_by!(card_number: card_number), false] if inserted.rows.empty?

    [find(inserted.rows.first.first), true]
  end
end
