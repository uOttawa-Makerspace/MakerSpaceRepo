Report Generator Controller creates the html view with charts and all, and is responsible for handling the POST parameters coming from the form. services/report_generator.rb is a plain old ruby object that generates spreadsheets using the Axlsx gem. https://github.com/caxlsx/caxlsx Check out the examples they're really nice.

Note that they both use different methods to fetch their data, and I hope to make the html version fetch everything from the service. This is the main reason why we're getting inaccurate reports. Passing dates as strings, subtle join/left_joins omitting results, even pluck/select gives different results sometimes.

Try not to hard code or assume anything, since literally any changes to schema or adding/removing new data might break the report generator.

look at https://api.rubyonrails.org/classes/ActiveRecord/QueryMethods.html

lab_sessions tracks visits and taps on each card reader

All programs and faculties are stored as strings, the only authority is the CSV located in `/lib/assets/programs.csv`.
