# Renders a Trix rich text editor: a hidden input holding the HTML plus the
# <trix-editor> element bound to it. Used by `form.trix_editor :field` (see
# config/initializers/trix_editor.rb) and by `trix_editor_tag` outside a form
# builder.
module TrixFieldsHelper
  mattr_accessor :id, instance_accessor: false, default: 0

  def trix_editor_tag(name, value = nil, options = {})
    options = options.symbolize_keys
    css_class = Array.wrap(options.delete(:class)).join(" ")
    attributes = {
      class: "formatted_content trix-content #{css_class}".squish,
      input: "trix_input_#{TrixFieldsHelper.id += 1}"
    }.merge(options)

    hidden_field_tag(name, value, id: attributes[:input]) + content_tag("trix-editor", "", attributes)
  end

  def trix_editor(object_name, method, options = {})
    TrixFieldsHelper::Field.new(object_name, method, self, options).render
  end

  # The field used by form builders: names, ids and the current value come
  # from the builder's object.
  class Field < ActionView::Helpers::Tags::Base
    delegate :dom_id, to: :@template_object

    def render
      options = @options.stringify_keys
      add_default_name_and_id(options)
      options["input"] ||= dom_id(object, [options["id"], :trix_input].compact.join("_"))
      value = options.delete("value") { value_before_type_cast }
      @template_object.trix_editor_tag(options.delete("name"), value, options)
    end
  end
end
