module Admin::UsersHelper
  def rfid_options_list(rfids, user)
    list = rfids.map{|r|
      label = "#{r.card_number} (#{time_ago_in_words(r.created_at)})"
      [label, r.id]
    }
    name = if user.rfid
             "#{user.rfid.card_number} (current)"
           else
             "Unset"
           end
    list.unshift([name, nil])
  end
end
