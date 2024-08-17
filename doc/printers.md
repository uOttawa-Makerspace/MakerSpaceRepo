# Printers

Whoever did the controllers markup is an idiot. Why use divs for headers? What's wrong with an h1 dude.

Printers have a printer type and a number. 'name' is a method that gets the printer number and a printer type short code.

# Printer Issue Tracker

Github 2.0???

Issue tracker lists all summaries, searches for specific keywords, and properly tags them as in the 'summaries' hash.

Reopening issues might cause problems with model validations: When reopening a closed issue with the same summary as a currently active issue. AKA when someone sends 'nozzle clogged', closes it, sends another one, then tried to re-open an issue with a similar.
