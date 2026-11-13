# frozen_string_literal: true

module Admin::UsersHelper
  def rfid_options_list(rfids, user)
    list =
      rfids.map do |r|
        if r.mac_address.present?
          location =
            PiReader.find_by_mac(r.mac_address).try(:pi_location)
          location =
            if location.nil?
              " - #{r.mac_address}"
            else
              " - #{location} [#{r.mac_address}]"
            end
        end
        label =
          "#{r.card_number} (#{t('admin_area.time_ago', time: time_ago_in_words(r.created_at))})#{location}"
        [label, r.id]
      end
    name = (user.rfid ? t("admin_area.users.rfid_current", card: user.rfid.card_number) : t("admin_area.users.rfid_unset"))
    list.unshift([name, nil])
  end

  # The user search filters: a label in the page language for each value the search accepts.
  def admin_user_search_filters
    Admin::UsersController::SEARCHABLE_FILTERS.map { |filter| [t("admin_area.users.filters.#{filter.downcase}"), filter] }
  end
end
