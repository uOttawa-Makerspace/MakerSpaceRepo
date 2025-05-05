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

# General schedule

- Start time
- End time
- Ordering - because some events might overlap
- Event title in english
- Event title in french
- Type of schedule (judge or student)

# Operation

A design day record is created, with a unique ID and a unique academic year
combination. General schedules are created, given a type, and have a foreign key
to a design day.

The controller exposes the usual CRUD routes, plus a route that would return the
most recent active design day configuration.

# Nested attributes

A bit messy, I tried to separate it into a generic JS plugin you could use
elsewhere. Currently written for design day only, if used elsewhere should be
moved to application or a separate JS file.

https://api.rubyonrails.org/classes/ActiveRecord/NestedAttributes/ClassMethods.html
