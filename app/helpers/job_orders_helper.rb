module JobOrdersHelper
  # The default shown in a number input. Browsers only accept "58.50" there, whatever the page language, so
  # this must not follow the locale's separators.
  def money_input_value(amount)
    number_with_precision(amount, precision: 2, separator: ".", delimiter: "")
  end

  def next_step
    new_job_order_path(step: @step + 1)
  end

  def previous_step
    new_job_order_path(step: @step - 1)
  end
end
