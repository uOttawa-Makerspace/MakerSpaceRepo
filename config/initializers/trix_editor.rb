# form.trix_editor :field, class: "form-control"
ActiveSupport.on_load(:action_view) do
  ActionView::Helpers::FormBuilder.class_eval do
    def trix_editor(method, options = {})
      @template.trix_editor(@object_name, method, objectify_options(options))
    end
  end
end
