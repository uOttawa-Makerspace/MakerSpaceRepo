# Design Day configuration

The website is hosted at designday.makerepo.com and is a React single page
application. The goal of the design day admin page is to eliminate the need for
developers to manually modify `config.ts` every year.

**Question:** Should this be a singular resource? As in, do we want to keep
track of changes from one year to another?

# What makes day a design?

- Exact start date
  - From this we derive the academic semester: year + (Fall/Winter/Summer)
- Google sheet ID
- Is active

And later, a way to modify:

- Floor plans
- Sponsors

Would the sponsor images look nice if auto generated? And who would host it - I
don't want makerepo serving these images if cloudflare already does

# General schedule

- Start time
- End time
- Ordering - because some events might overlap
- Event title in english
- Event title in french
- Type of schedule (judge or student)

# Operation

A design day record is created, with a unique google sheet ID (called key for
some reason in DB) and a unique academic year combination. General schedules are
created, given a type, and have a foreign key to a design day.

Each design day contains multiple design day schedules. Each schedule has a
start and end time, whether the event is meant for students or judges, a title
in english and french, and an optional ordering integer.

Because ordering is explicitly set by admins, we sort by that primarily then
sort by the start time of the schedule event.

The controller is defined with a singular resource route - that is, there's no
index or create method, only show and update. There's a singleton method defined
on the `DesignDay` class itself that returns the first instance made. Really
there's only one design day ever and I don't see a reason for keeping the data
for other days around, other than for record-keeping sake.

# Nested attributes

A bit messy and complicated, but does make the API simpler from a POST request
perspective. I tried to implement the form generation functions as generic JS
functions you could use elsewhere. Currently written and implemented for design
day only, if used elsewhere should be moved to application or a separate JS
file.

https://api.rubyonrails.org/classes/ActiveRecord/NestedAttributes/ClassMethods.html

The current API effectively takes the entire schedule list and does a replace
instead of a copy. You could enable updates, but then each schedule sent would
need an ID transmitted too. Keep it simple, admins don't use curl.
