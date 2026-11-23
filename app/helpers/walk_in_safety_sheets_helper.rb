module WalkInSafetySheetsHelper
  # Make a checkbox with some text around it
  def agree_check_box(name, f)
    label = f.label(name, class: 'form-check-label') do
      yield if block_given? # display agreement text
    end
    check_box = f.check_box(name, name: 'agreement[]', class: 'form-check-input fs-3',
                            required: true, include_hidden: false,
                            checked: f.object.persisted?, disabled: f.object.persisted?)
    tag.div(label + check_box, class: 'form-check mb-3')
  end
end
