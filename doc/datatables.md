# How are tables done

**NOTE: This document is a in-progress, feel free to add on to it if needed**

Tables on MakerSpaceRepo are a bit of a hassle right now. There's a multitude of
different ways tables are used on the website, and some aren't fully functional
with Turbo disabled. The most common way used to be a script attached to an icon
on the website.

We use [DataTables](https://datatables.net/) as a JS table plugin. The plugin
offers pagination, type-aware sorting, search, and bootstrap integration. We've
tried to hand-roll our own solutions for some time, but this seems to be the
most time-efficient solution considering our existing manpower.

The plugin is extremely flexible and I highly recommend you look at the official
documentation and forums. They are very good and have covered probably
everything I've ever had to lookup.

# Using DataTables

The plugin is used for progressive enhancement. That is, it is initialized with
HTML tables already present. Currently for any table we have a custom attribute
`data-datatable` to load the plugin into any table. The source for the global
attribute is defined in `/app/javascript/entrypoints/tabledata.js`. Right now
this is literally just a loop on a selector.

Table-specific configuration can be set with attributes on the `<table>`
element. For anything too advanced to be done with HTML attributes, the
controller javascript is loaded after the application script. You should however
reconsider whether post-initialization javascript is required for what is
essentially static configuration.

For more information on how to use data attributes:

- [Table specific configuration](https://datatables.net/examples/advanced_init/html5-data-options.html)
- [Cell specific configuration](https://datatables.net/examples/advanced_init/html5-data-attributes.html)

# Pagination

The plugin auto-paginates rows delivered via HTML, and also supports server-side
pagination. Right now the easiest option is to return all rows in a database and
have the client sort it out client side.

Client-side pagination is obviously unreliable for long term. Some views such as
the job orders page can return hundreds of rows. A proper solution is to
implement server-side pagination as a shared Rails concern. The concern should
be easy enough to use and quickly plug into any route that returns a page.

- [Server-side processing](https://datatables.net/examples/data_sources/server_side.html)

# References

Read these:

- https://datatables.net/examples/data_sources/dom.html
