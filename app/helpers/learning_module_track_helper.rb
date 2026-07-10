module LearningModuleTrackHelper
  def status_button(learning_module_track)
    return unless learning_module_track
    
    status = learning_module_track&.status || 'not_started'
    localized =
      t(
        "learning_module_track.status.#{status}",
        default: t('learning_module_track.status.not_started')
      )

    color =
      (
        if learning_module_track&.completed?
          'text-success border-success'
        else
          'text-secondary border-secondary'
        end
      )

    tag.span class: "btn btn-sm #{color} mt-auto w-100",
             role: 'status',
             aria: {
               label: "Status: #{localized}"
             } do
      localized
    end
  end
end
