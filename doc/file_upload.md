# How to make attachments

Back in the day we had carrierwave and paperclip and stuff. Now Active Storage comes built in and took over everything through sheer virtue of being built into the framework.

The paperclip gem had a limitation of one attachment per model, so `Photo` was a model to work around that. Only a few models really depend on it.

https://thoughtbot.com/blog/closing-the-trombone

Active Storage came out and the paperclip guys themselves said that it's over. Thankfully we've already migrated the metadata over so we don't need to re-upload the files through Active Storage. The model remains however and I think that's annoying.
