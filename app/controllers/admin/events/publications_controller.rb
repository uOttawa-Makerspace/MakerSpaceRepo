# frozen_string_literal: true

# Takes a published event back to draft and removes its Google copy.
class Admin::Events::PublicationsController < AdminAreaController
  def destroy
    event = Event.find(params[:event_id])
    google_event_id = event.google_event_id
    calendar_id = event.google_calendar

    if event.unpublish(by: current_user)
      Event.remove_from_google_later(google_event_id, calendar_id, event.id)
      flash[:notice] = "Event unpublished successfully."
    else
      flash[:alert] = validation_message(event, "failed_saves.event_unpublish")
    end

    redirect_back(fallback_location: admin_calendar_index_path)
  end
end
