# MakerSpaceRepo Project Structure

## Important Files/Directories

- `/app`: contains most of the files that are used in the app
- `/app/assets/stylesheets`: contains SASS (.scss) stylesheets used for custom styling
  - **Note**: Most of the time, we use Boostrap for styling as it is fast and easy
- `/app/controllers`: contains the controllers that handle HTTP requests within our app
- `/app/javascript/entrypoints`: contains javascript files that are run on the client's browser
- `/app/mailers`: contains files that handle sending emails
- `/app/models`: contains the models that manage data within our application
- `/app/views`: contains directories of HTML files which act as the user interface

- `/db`: contains the database schema and migration files

  - **Note**: `/db/schema.rb` should only be modified from migrations and should not be directly modified

- `/config/routes.rb`: contains all the HTTP routes within our app
- `/config/schedule.rb`: contains CRON jobs that are run at specific intervals
- `/config/locales`: contains the english and french translation files used in certain parts of the app

- `/spec`: contains tests & factories that are used in our github workflow

## Important App Areas

- **Note**: There are a lot of areas/features in the app. If there is a certain area or feature in the app that you don't understand, don't be afraid to ask a supervisor or manager who is more knowledgeable on MakerSpaceRepo

### Admin Area

- Contains areas in the app in which only admins can access
- Can be accessed from: `Navbar --> Profile Dropdown --> Admin Area`
- **Note**: All admin-only controllers in the app should inherit from `AdminAreaController`

### Staff Area

- Contains areas in the app in which only admins or staff can access
- Can be accessed from: `Navbar --> Profile Dropdown --> Staff Area`
- **Note**: All staff controllers in the app should inherit from `StaffAreaController`

### MakerRoom

- MakerRoom is a booking system within our app that allows users to book rooms in various spaces
- User bookings are either approved automatically or manually reviewed by an admin depending on the space
- Users must be admins or apply to be room bookers
- Can be accessed from: `Navbar --> More --> MakerRoom`

- Model: `/app/models/sub_space_booking.rb`
- Views: `/app/views/sub_space_booking`
- Controller: `/app/controllers/sub_space_booking_controller.rb`
- Javascript: `/app/javascript/entrypoints/sub_space_booking.js`

- Note: We use [FullCalendar](https://fullcalendar.io/) for MakerRoom, Shifts, and Unavailabilities

### Shifts (Admin Area)

- Shifts is a calendar system in which admins can manage their staff's work shifts on a weekly-basis
- Admin Shifts can be accessed from:
  - `Navbar --> Profile Dropdown --> Admin Area --> Staff Management Dropdown --> Shifts`
  - URL: `/admin/shifts/shifts`
- Staff can view their shifts (but can't edit them) at:

  - `Navbar --> Profile Dropdown --> Staff Area --> Shifts`
  - URL: `/staff/shifts_schedule`

- Model: `/app/models/shift.rb`
- Views: `/app/views/admin/shifts`
- Controller: `/app/controllers/admin/shifts_controller.rb`
- Javascript: `/app/javascript/entrypoints/admin_shifts.js`

### Unavailabilities (Admin Area)

- Unavailabilities is a calendar system in which admins can view and manage their staff's unavailabilities
- Admin Unavailabilities can be accessed from:
  - `Navbar --> Profile Dropdown --> Admin Area --> Staff Management Dropdown --> Unavailabilities`
  - URL: `/admin/shifts`
- Staff can view and enter their unavailabilities at:

  - `Navbar --> Profile Dropdown --> Profile --> Staff Dropdown --> Staff Unavailabilities`
  - URL: `/staff_availabilities`

- Model: `/app/models/staff_availability.rb`
- Views: `/app/views/staff_availabilities`
- Controller: `/app/controllers/staff_availabilities_controller.rb`
- Javascript: `/app/javascript/entrypoints/admin_availability_calendar.js`
