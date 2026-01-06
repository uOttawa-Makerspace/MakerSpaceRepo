# frozen_string_literal: true

# replace <div class="field_with_error"> with class="is-invalid" for Bootstrap
ActionView::Base.field_error_proc =
  proc do |html_tag, _instance|
    def format_error_message_to_html_list(html_tag, _instance)
      if !html_tag.include?("<label")
        return unless _instance.error_message.present?

        "<div class='invalid-feedback'>#{_instance.error_message.join(", ")}</div>"
      else
        ""
      end
    end
    class_attr_index = html_tag.index 'class="'

    if class_attr_index
      html_tag.insert class_attr_index + 7, "is-invalid "
    else
      html_tag.insert html_tag.index(">"), ' class="is-invalid"'
    end
    html_tag + sanitize(format_error_message_to_html_list(html_tag, _instance))
  end
