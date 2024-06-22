Report Generator Controller creates the html view with charts and all, and is responsible for handling the POST parameters coming from the form. services/report_generator.rb is a plain old ruby object that generates spreadsheets using the Axlsx gem. https://github.com/caxlsx/caxlsx Check out the examples they're really nice.

Note that they both use different methods to fetch their data, and I hope to make the html version fetch everything from the service. This is the main reason why we're getting inaccurate reports. Passing dates as strings, subtle join/left_joins omitting results, even pluck/select gives different results sometimes.

Try not to hard code or assume anything, since literally any changes to schema or adding/removing new data might break the report generator.

look at https://api.rubyonrails.org/classes/ActiveRecord/QueryMethods.html

lab_sessions tracks visits and taps on each card reader

All programs and faculties are stored as strings, the only authority is the CSV located in `/lib/assets/programs.csv`.

# University Program crash course

There's a userscript in `/scripts` that fetches and attempts to create a csv of all programs, their study level, faculty, and engineering department if applicable. It can also make a JSON, if you uncomment out the appropriate code

It returns duplicates, because some programs are listed under multiple faculties/levels. For example, the lettres francaise/education is listed under Arts and Education. A molecular biology double degree is listed under Bachelor's and PhD.
The `ProgramList` class does not attempt to filter those out; either fix the CSV data to avoid duplicates, by dropping/merging unnecessary duplicates, or generate unique lists on the spot when needed.
