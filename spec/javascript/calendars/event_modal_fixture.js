// A trimmed copy of app/views/admin/calendar/_form.html.erb: every element the
// calendar scripts read or write, with the same ids and classes.
export const EVENT_MODAL_HTML = `
<button type="button" id="addEventButton"></button>
<div id="staff_load_error" class="d-none" role="alert"></div>
<input type="hidden" id="space_id" value="7">
<div id="content">
<div class="modal fade" id="eventModal">
  <h5 id="eventModalLabel">Add Event</h5>
  <form id="eventForm" action="/admin/events" method="post">
    <div id="staff_select_container" class="mb-3">
      <select name="staff_select[]" id="staff_select" multiple></select>
    </div>
    <input type="checkbox" id="all_day_checkbox">
    <input type="datetime-local" name="event[start_time]" id="start_time_field">
    <input type="datetime-local" name="event[end_time]" id="end_time_field">
    <div id="time_error" class="d-none"></div>
    <select id="recurrence_frequency">
      <option value="">Does not repeat</option>
      <option value="DAILY">Daily</option>
      <option value="WEEKLY">Weekly</option>
      <option value="MONTHLY">Monthly</option>
    </select>
    <div id="recurrence_options" style="display: none;">
      <input type="date" id="recurrence_until">
      <div id="weekly_options" style="display: none;">
        ${["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
          .map(
            (d) =>
              `<input class="dayCheckbox" type="checkbox" value="${d}" id="day_${d}">`,
          )
          .join("")}
        <div id="day_freq_error" class="d-none"></div>
      </div>
    </div>
    <div class="mb-3">
      <select name="event[event_type]" id="event_type_select">
        <option value="">Select an event type</option>
        <option value="shift">Shift</option>
        <option value="training">Training</option>
        <option value="meeting">Meeting</option>
        <option value="other">Other</option>
        <option value="unavailability">Unavailability</option>
      </select>
    </div>
    <div id="training-fields" style="display: none;">
      <select name="event[training_id]" id="training_select"><option value=""></option><option value="3">Laser</option></select>
      <select name="event[language]" id="language_select"><option value=""></option><option value="en">English</option></select>
      <select name="event[course_name]" id="course_select"><option value=""></option><option value="9">GNG</option></select>
    </div>
    <input type="hidden" name="event[utc_start_time]" id="utc_start_time">
    <input type="hidden" name="event[utc_end_time]" id="utc_end_time">
    <input type="hidden" name="event[recurrence_rule]" id="recurrence_rule_field">
    <input type="hidden" name="event[space_id]" value="7">
    <div id="accordion"><div class="collapse"></div></div>
    <input type="text" name="event[title]" id="title">
    <textarea name="event[description]" id="description"></textarea>
    <div id="modal_buttons">
      <div id="save_button_container"><input type="submit" value="Save Draft" id="save_button"></div>
      <div id="update_dropdown" style="display: none;">
        <div id="update_dropdown_items">
          <input type="radio" name="update_scope" id="update_this" value="this" checked>
          <input type="radio" name="update_scope" id="update_all" value="all">
          <div id="dropdown_save_button_container"></div>
        </div>
      </div>
    </div>
  </form>
  <div id="publish_and_delete_forms" style="display: none;">
    <form id="publish_form" action="#" style="display: none;"></form>
    <form id="delete_single_form" action="#"><input class="delete_start_date" name="start_date"></form>
    <form id="delete_following_form" action="#"><input class="delete_start_date" name="start_date"></form>
    <form id="delete_all_form" action="#"></form>
  </div>
</div>
</div>`;

// The same for app/views/staff/unavailabilities/_form.html.erb.
export const UNAVAILABILITY_MODAL_HTML = `
<div id="content">
<button type="button" id="addUnavailabilityButton"></button>
<div class="modal fade" id="unavailabilityModal">
  <h5 id="unavailabilityModalLabel">Add Unavailability</h5>
  <form id="unavailForm" action="/staff/unavailabilities" method="post">
    <input type="checkbox" id="all_day_checkbox">
    <input type="datetime-local" id="start_time_field">
    <input type="datetime-local" id="end_time_field">
    <div id="time_error" class="d-none"></div>
    <select id="recurrence_frequency">
      <option value="">Does not repeat</option>
      <option value="DAILY">Daily</option>
      <option value="WEEKLY">Weekly</option>
      <option value="MONTHLY">Monthly</option>
    </select>
    <div id="recurrence_options" style="display: none;">
      <input type="date" id="recurrence_until">
      <div id="weekly_options" style="display: none;">
        ${["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
          .map(
            (d) =>
              `<input class="dayCheckbox" type="checkbox" value="${d}" id="day_${d}">`,
          )
          .join("")}
        <div id="day_freq_error" class="d-none"></div>
      </div>
    </div>
    <input type="hidden" id="utc_start_time">
    <input type="hidden" id="utc_end_time">
    <input type="hidden" id="recurrence_rule_field">
    <div id="accordion"><div class="collapse"></div></div>
    <input type="text" id="title">
    <textarea id="description"></textarea>
    <div id="modal_buttons">
      <input type="submit" value="Update" id="save_button">
      <div id="update_dropdown">
        <div id="update_dropdown_items"><input type="radio" name="update_scope" id="update_this" value="this" checked></div>
      </div>
    </div>
  </form>
  <div id="delete_forms" style="display: none">
    <form id="delete_single_form" action="#"><input class="delete_start_date" name="start_date"></form>
    <form id="delete_following_form" action="#"><input class="delete_start_date" name="start_date"></form>
    <form id="delete_all_form" action="#"></form>
  </div>
</div>
</div>`;
