module LockerRentalsHelper
  def locker_rental_actions(rental, for_admin = true)
    end_rental_button =
      button_to(
        t("lockers.actions.cancel_rental"),
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
        class: "btn btn-danger"
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
        class: "btn btn-success"
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
            state: :active
          }
        },
        method: :put,
        class: "btn btn-info"
      )

    return end_rental_button unless for_admin

    case rental.state.to_sym
    when :reviewing
      tag.div class: "btn-group" do
        ask_payment_button + instant_approve_button + end_rental_button
      end
    when :await_payment
      tag.div class: "btn-group" do
        instant_approve_button + end_rental_button
      end
    when :active
      tag.div class: "btn-group" do
        end_rental_button
      end
      #when :cancelled
    end
  end
end
