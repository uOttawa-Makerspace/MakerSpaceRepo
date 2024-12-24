module LockerRentalsHelper
  def locker_rental_actions(rental)
    end_rental_button =
      button_to(
        "Cancel",
        locker_rental_path(rental),
        data: {
          confirm: "Are you sure you want to cancel this locker rental?"
        },
        params: {
          locker_rental: {
            state: :cancelled
          }
        },
        method: :put,
        class: "btn btn-danger btn-sm"
      )
    ask_payment_button =
      button_to(
        "Send to checkout",
        locker_rental_path(rental),
        data: {
          confirm: "Are you sure you want to send request to checkout?"
        },
        params: {
          locker_rental: {
            state: :await_payment
          }
        },
        method: :put,
        class: "btn btn-success btn-sm"
      )
    instant_approve_button =
      button_to(
        "Assign now",
        locker_rental_path(rental),
        data: {
          confirm: "Are you sure you want to assign locker immediately?"
        },
        params: {
          locker_rental: {
            state: :await_payment
          }
        },
        method: :put,
        class: "btn btn-info btn-sm"
      )
    case rental.state.to_sym
    when :reviewing
      tag.div class: "btn-group p-0 m-0" do
        ask_payment_button + instant_approve_button + end_rental_button
      end
    when :await_payment
      end_rental_button
    when :active
      end_rental_button
      #when :cancelled
    end
  end
end
