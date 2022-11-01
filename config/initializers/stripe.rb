require "stripe"
Stripe.api_key =
  Rails.application.credentials[Rails.env.to_sym][:stripe][:api_key]
StripeEvent.signing_secret =
  "whsec_6fac98a8f7cf1ba928c44b2e1488afccd5f32ab300fb092502cfcf1f5ff96a16"
#  Rails.application.credentials[Rails.env.to_sym][:stripe][:webhook_secret_key]

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
