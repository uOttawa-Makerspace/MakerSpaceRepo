module LockerRentalsHelper
  def locker_rental_state_display(locker_rental)
    locker_rental_state_color = {
      'reviewing' => 'text-secondary',
      'await_payment' => 'text-info',
      'active' => 'text-success',
      'cancelled' => 'text-danger'
    }

    locker_rental_state_icon = {
      'active' => 'check',
      'cancelled' => 'clock-o'
    }

    tag.span class: locker_rental_state_color[locker_rental.state] do
      if locker_rental_state_icon[locker_rental.state]
        fa_icon locker_rental_state_icon[locker_rental.state], text: locker_rental.state.humanize
      else
        locker_rental.state.humanize
      end
    end
  end
end
