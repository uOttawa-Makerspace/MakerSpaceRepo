require "stripe"
Stripe.api_key =
  Rails.application.credentials[Rails.env.to_sym][:stripe][:api_key]
StripeEvent.signing_secret =
  Rails.application.credentials[Rails.env.to_sym][:stripe][:webhook_secret_key]

# NOTE: We don't use stripe anymore and all of the systems here have been
# overhauled. These callbacks probably do not work anymore.
StripeEvent.configure do |events|
  events.subscribe "payout.paid" do |event|
    obj =
      Stripe::Payout.retrieve(id: event.data.object.id, expand: ["destination"])
    date = Time.at(obj.arrival_date).strftime("%Y-%m-%d")

    MsrMailer.send_email_for_stripe_transfer(
      obj.id,
      date,
      obj.amount,
      obj.destination.bank_name,
      obj.destination.routing_number
    ).deliver_now
  end

  events.subscribe "checkout.session.completed" do |event|
    return unless event.data.object.payment_status === "paid"
    # job orders
    if event.data.object.client_reference_id.include?("job-order-")
      jo =
        JobOrder.find(
          event.data.object.client_reference_id.gsub("job-order-", "")
        )
      if jo.present?
        jo.job_order_statuses << JobOrderStatus.create(
          job_order: jo,
          job_status: JobStatus::PAID,
          user: jo.user
        )
        jo.job_order_quote.update(stripe_transaction_id: event.data.object.id)
        JobOrderMailer.payment_succeeded(jo.id).deliver_now
      end
    elsif event.data.object.client_reference_id.include?("locker-rental-")
      locker_rental =
        LockerRental.find(
          event.data.object.client_reference_id.gsub("locker-rental-", "")
        )
      # state change, auto assign, and sends mail
      locker_rental.auto_assign if locker_rental.present?
    end
  end

  events.subscribe "checkout.session.async_payment_succeeded" do |event|
    if event.data.object.payment_status === "paid" &&
         event.data.object.client_reference_id.include?("job-order-")
      jo =
        JobOrder.find(
          event.data.object.client_reference_id.gsub("job-order-", "")
        )
      if jo.present?
        jo.job_order_statuses << JobOrderStatus.create(
          job_order: jo,
          job_status: JobStatus::PAID,
          user: jo.user
        )
        jo.job_order_quote.update(stripe_transaction_id: event.data.object.id)
        JobOrderMailer.payment_succeeded(jo.id).deliver_now
      end
    elsif event.data.object.client_reference_id.include?("locker-rental-")
      locker_rental =
        LockerRental.find(
          event.data.object.client_reference_id.gsub("locker-rental-", "")
        )
      # state change, auto assign, and sends mail
      locker_rental.auto_assign if locker_rental.present?
    end
  end

  events.subscribe "checkout.session.async_payment_failed" do |event|
    if event.data.object.payment_status === "paid" &&
         event.data.object.client_reference_id.include?("job-order-")
      jo =
        JobOrder.find(
          event.data.object.client_reference_id.gsub("job-order-", "")
        )
      JobOrderMailer.payment_failed(jo.id).deliver_now if jo.present?
    end
  end
end
