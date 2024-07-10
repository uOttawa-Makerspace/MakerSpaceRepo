# CEEDRepo yay

The new homepage is implemented in `static_pages/home_redesign.html.erb` This should be renamed to replace the old home page. Tests will fail until then, just to make sure we fully replace the old one.

Three columns, the middle one being wider than the others.

## Navbar:

`app/javascript/entrypoints/header.js` contains scripts for scrolling the header navbar. It is currently disabled and really would rather refactor it than just re-enable and patch it.

Other pages (volunteer page) might add their own navbar at the top, these are conditionally loaded in header as well

The dropdown menus have a little triangle at the top, added to all dropdowns in `application.scss`

## Newletter:

Newsletter is run by mailchimp, a form at the footer and another one in the right column.

## Links

The links are orange on white, which sucks a lot I think.

## Tiles

The tiles are implemented as bootstrap cards, though to be honest they don't do much really as we have our own `home-card` class that overrides a lot of the styles it adds. Still we keep it in case someone wants masonry layouts in the future

## Icons

FontAwesome is ancient, and in the redesign we replace it with bootstrap icons. Do a ripgrep search for the .fa class in stylesheets, html, and ERB.

## Localization

The home page has it's own separate localization files, `locales/home-*.yml`. Rails auto loads all YAML files and merges them into the localization database. Maybe split other views into their own localization files?

## Development/Volunteer program

Badges and skills are lifted from the user profile page
Skills are certifications?? Limit the count of skills, some have a lot of skills. Display level not number
We do track progress, it is

All badges have a skill, not all skills have a badge associated. There should be one for every but we didn't create enough badges. Someone might have a skill with no badge to show for it :(.

Vector graphics is NOT a workshop we give, but it is a skill in the development program. No badge for it too.

Basic java is a workshop, shown in the list because when after the workshop we give certification. No learning module, no proficiency project, etc. for it.

Development program has learning modules:
green number is beginner, yellow is intermediate. not much learning modules :^).
People should look at all the learning modules, do a proficiency project, then get a badge for it. That'

Think of a way to clean up or clearly explain all of this. Maybe change terminology or link paths.
There isn't a corresponding project/badge/workshop for all skills, make that clear somehow...

Maybe make a summary project? Step one was learning modules, step two was the projects, step three was the badges.

You can be in progress of a development program skill, but not in progress in a workshop session. Skills should only display level instead.

## BUG HUNT DUTY

Fix white links, headers are weird, roll them into one div. For non-engineering students show faculty instead of department, ARIA labels, responsive layout

work term report, mdi term eval by supervisor, and update resume
