# frozen_string_literal: true

module PrintOrdersHelper

  def return_checked(value, label)
    if label == value
      'checked'
    else
      ''
    end
  end

  def return_checked_other(value)
    if (value != 'PLA') && (value != 'ABS') && (value != 'SST') && (value != 'M2 Onyx') && (value != 'Low Quality') && (value != 'Medium Quality') && (value != 'High Quality')
      'checked'
    end
  end

  def check_value(value)
    if return_checked_other(value) == 'checked'
      value
    end
  end

end
