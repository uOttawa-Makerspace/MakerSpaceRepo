# CEEDRepo yay

The new homepage is implemented in `static_pages/home_redesign.html.erb` This should be renamed to replace the old home page. Tests will fail until then, just to make sure we fully replace the old one.

Three columns, the middle one being wider than the others.

Mobile view is implemented by hiding tiles based on screen size. Bootstrap offcanvas is used for the shortcuts link up top

## PLEASE USE REM IN CSS, DO NOT USE PX

It's <%= Date.today.year %>, use rem in your CSS and not px. It's responsive for mobile dev and is based on the parent's font size (16px default, but we mess with it a bit). You can use it for everything, margin, padding, line height, anywhere instead of px. A lot of legacy css still uses px, feel free to be a hero and calculate the equivalent rem value :^)

## Navbar:

`app/javascript/entrypoints/header.js` contains scripts for scrolling the header navbar. It is currently disabled and really would rather refactor it than just re-enable and patch it.

Other pages (volunteer page) might add their own navbar at the top, these are conditionally loaded in header as well

The dropdown menus have a little triangle at the top, added to all dropdowns in `application.scss`

## Newletter:

Newsletter is run by mailchimp, a form at the footer and another one in the right column. The user ID is constant for both, but we switch out the newsletter ID depending on locale

## Tiles

The tiles are implemented as bootstrap cards, though to be honest they don't do much really as we have our own `home-card` class that overrides a lot of the styles it adds. Still we keep it in case someone wants masonry layouts in the future

## Icons

FontAwesome is ancient, and in the redesign we replace it with bootstrap icons. Do a ripgrep search for the .fa class in stylesheets, html, and ERB.

## Localization

The home page has it's own separate localization files, `locales/home-*.yml`. Rails auto loads all YAML files and merges them into the localization database. Maybe split other views into their own localization files?

## BUG HUNT DUTY

Fix white links and buttons, green headers and text.
