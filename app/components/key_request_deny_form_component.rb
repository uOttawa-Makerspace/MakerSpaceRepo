# One form to deny a key request: an optional reason and a confirmation on the form.
class KeyRequestDenyFormComponent < ViewComponent::Base
  def initialize(key_request:, form_class: nil, input_class: nil, button_class: nil, icon: false)
    @key_request = key_request
    @form_class = form_class
    @input_class = input_class
    @button_class = button_class
    @icon = icon
  end

  private

  attr_reader :key_request, :form_class, :input_class, :button_class, :icon

  def field_id
    "denial_reason_#{key_request.id}"
  end

  def url
    deny_key_request_admin_keys_path(id: key_request.id)
  end
end
