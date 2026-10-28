require "stripe"

stripe_api_key = Rails.application.credentials.dig(Rails.env.to_sym, :stripe, :api_key)
stripe_signing_secret = Rails.application.credentials.dig(Rails.env.to_sym, :stripe, :webhook_secret_key)

Stripe.api_key = stripe_api_key if stripe_api_key.present?
StripeEvent.signing_secret = stripe_signing_secret if stripe_signing_secret.present?

# NOTE: We don't use stripe anymore and all of the systems here have been
# overhauled. Job-order payments are no longer recorded from Stripe (chunk 20a);
# staff set the "Paid" status by hand.
StripeEvent.configure do |events|
  events.subscribe "payout.paid" do |event|
    obj = Stripe::Payout.retrieve(id: event.data.object.id, expand: ["destination"])
    date = Time.zone.at(obj.arrival_date).strftime("%Y-%m-%d")

    MsrMailer.send_email_for_stripe_transfer(
      obj.id,
      date,
      obj.amount,
      obj.destination.bank_name,
      obj.destination.routing_number
    ).deliver_now
  end

  events.subscribe "checkout.session.completed" do |event|
    next unless event.data.object.payment_status == "paid"

    if event.data.object.client_reference_id.include?("locker-rental-")
      locker_rental = LockerRental.find_by(id: event.data.object.client_reference_id.delete_prefix("locker-rental-"))
      locker_rental.presence&.auto_assign
    end
  end

  events.subscribe "checkout.session.async_payment_succeeded" do |event|
    next unless event.data.object.payment_status == "paid"

    if event.data.object.client_reference_id.include?("locker-rental-")
      locker_rental = LockerRental.find_by(id: event.data.object.client_reference_id.delete_prefix("locker-rental-"))
      locker_rental.presence&.auto_assign
    end
  end
end
