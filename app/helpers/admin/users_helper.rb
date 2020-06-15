# frozen_string_literal: true

module Admin::UsersHelper
  def rfid_options_list(rfids, user)
    list = rfids.map do |r|
      if r.mac_address.present?
        location = PiReader.find_by(pi_mac_address: r.mac_address).try(:pi_location)
        location = if location.nil?
                     " - #{r.mac_address}"
                   else
                     " - #{location} [#{r.mac_address}]"
                   end
      end
      label = "#{r.card_number} (#{time_ago_in_words(r.created_at)} ago)#{location}"
      [label, r.id]
    end
    name = if user.rfid
             "#{user.rfid.card_number} (current)"
           else
             'Unset'
           end
    list.unshift([name, nil])
  end
end
