module JobOrdersHelper
  # The default shown in a number input. Browsers only accept "58.50" there, whatever the page language, so
  # this must not follow the locale's separators.
  def money_input_value(amount)
    number_with_precision(amount, precision: 2, separator: ".", delimiter: "")
  end

  # A listed service with the price per unit this user pays, in the page language: "PLA ($15.0/g)".
  def job_service_label(service, user)
    price = user.internal? ? service.internal_price : service.external_price
    t("job_orders.wizard.step_2.service_with_price", name: service.name, unit: service.unit,
                                                     price: number_with_delimiter(price, delimiter: ""))
  end

  def next_step
    new_job_order_path(step: @step + 1)
  end

  def previous_step
    new_job_order_path(step: @step - 1)
  end
end
