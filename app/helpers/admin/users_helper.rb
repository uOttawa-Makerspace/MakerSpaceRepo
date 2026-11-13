# frozen_string_literal: true

module Admin::UsersHelper
  def rfid_options_list(rfids, user)
    readers = PiReader.readers_by_mac(rfids.map(&:mac_address))
    list =
      rfids.map do |r|
        if r.mac_address.present?
          location = readers[r.mac_address]&.pi_location
          location =
            if location.nil?
              " - #{r.mac_address}"
            else
              " - #{location} [#{r.mac_address}]"
            end
        end
        label =
          "#{r.card_number} (#{time_ago_in_words(r.created_at)} ago)#{location}"
        [label, r.id]
      end
    name = (user.rfid ? "#{user.rfid.card_number} (current)" : "Unset")
    list.unshift([name, nil])
  end
end
