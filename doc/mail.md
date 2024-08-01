# Sending mail using mailers

A lot of the old mails are simply copy pastes of each other, the print_failed email from `MsrMailer` is the only one that uses the `msr_mailer` layout. Because there's a ton of emails and not all of them might fit nicely in the layout, we selectively add them with a format block. It should've been an `application_mailer` layout to cover ALL emails. Someone should move all emails to that layout and have it global instead :^)

`MsrMailer` (or MakerSpaceRepo Mailer) is the big mailer that contains almost all mails, from welcome to restore passwords, proficient project results and print jobs. There's other smaller ones for job orders, booking, etc. Feel free to create new mailers, but make sure you create a layout for them first. Tests are important for those, since admin and staff almost never receive these emails and users are quick to notice something broken.

Rails has support for multipart email, or sending both html and text in the same email. We should do that sometime, maybe do `strip_tags(@message)` in the body. It's mostly an accessibility thing since some users might prefer text emails instead of html. Otherwise, enabling text in an email will give a 'template missing error'.

We have two editable mail templates, the Job Order email and the print failed email. Both are being stored in the `JobOrderMessage` table, because previously it was a table containing a single row with the job order mail template. Each message has a unique name and is retrieved with a scope and formatted with a function.

## Mail basics

Mail should have a descriptive subject that explains the entire mail before the user even opens it; when viewed from an inbox list or a phone notification drawer. The body should repeat the subject, and elaborate on what actions the user can perform. Keep in mind not all Makerepo users are engineering students, a lot are not university students or are students from other faculties.

The body should include only text and anchor links, buttons are not a good idea as they are not supported by any version of Outlook on Windows. See below.

All mail should have a reason for sending at the bottom, print_failed provides a `:why_received` for the `msr_mailer` layout.

Any mail send is done similar to `MsrMailer.welcome_mail(user).deliver_now`. If the `deliver_now` method isn't called, it'll be stored in a job queue for later delivery. I'm not sure if we have a cron job or rake task for that setup.

## Email editing

Some emails have editable messages, like the job order message and the printer falied message. These messages are usually made editable with a `trix_editor` tag. Messages are stored as html fragments in `JobOrderMessage` and each have a scope for quick access. They also have a formatting method that takes in parameters and returns a string containing html tags, or the unformatted message.

## Testing email

To test email on staging, we have the `letter_opener` gem installed as a mail handler.

To test emails, open a rails console (`rails c` in a terminal or `projectile-rails-console` in emacs) and do `MsrMailer.welcome_email(User.find_by_id(25)).deliver_now`. This will simulate a mail delivery and open it in your browser. All generated emails are stored in `tmp/letter_opener/`.

## Email HTML

Email HTML is **very** broken, see https://www.caniemail.com/ for what little you can use. More generally, inline styles only and table layouts and simple text are the only thing that works here. University uses outlook for mail, and outlook on windows uses Word as a rendering engine, while you're probably using an actual web browser. So be very careful with layout, and don't a lot of fancy css for accessibility reasons too.
