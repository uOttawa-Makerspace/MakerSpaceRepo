# form.trix_label :field, "Text"
# form.trix_editor :field, class: "form-control"
#
# The label gets the id field_id(:field, :label) and the editor is named by it
# through aria-labelledby: a <trix-editor> is not a labelable element, so a
# label's `for` does not name it. Pass aria: { label: ... } to name an editor
# that has no visible label.
ActiveSupport.on_load(:action_view) do
  ActionView::Helpers::FormBuilder.class_eval do
    def trix_label(method, text = nil, options = {})
      label(method, text, options.reverse_merge(id: field_id(method, :label)))
    end

    def trix_editor(method, options = {})
      @template.trix_editor(@object_name, method, objectify_options(named_by_label(method, options)))
    end

    private

    def named_by_label(method, options)
      aria = options[:aria] || {}
      return options if aria[:label] || aria[:labelledby]

      options.merge(aria: aria.merge(labelledby: field_id(method, :label)))
    end
  end
end
