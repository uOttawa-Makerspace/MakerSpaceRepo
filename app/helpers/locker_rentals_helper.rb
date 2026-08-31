module LockerRentalsHelper
  def locker_rental_state_display(locker_rental)
    return '' unless locker_rental

    locker_rental_state_color = {
      'reviewing' => 'badge text-bg-secondary',
      'await_payment' => 'badge text-bg-info',
      'active' => 'badge text-bg-success',
      'cancelled' => 'badge text-bg-danger'
    }

    locker_rental_state_icon = {
      'reviewing' => 'fa-solid fa-hourglass-half',
      'await_payment' => 'fa-solid fa-credit-card',
      'active' => 'fa-solid fa-circle-check',
      'cancelled' => 'fa-solid fa-circle-xmark'
    }

    color_class = locker_rental_state_color[locker_rental.state] || 'badge text-bg-secondary'
    icon_class = locker_rental_state_icon[locker_rental.state]

    tag.span class: color_class do
      if icon_class
        concat tag.i(class: "#{icon_class} me-1")
      end
      concat locker_rental.state.humanize
    end
  end
end
