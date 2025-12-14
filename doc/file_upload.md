# How to make attachments

Back in the day we had carrierwave and paperclip and stuff. Now Active Storage comes built in and took over everything through sheer virtue of being built into the framework.

The paperclip gem had a limitation of one attachment per model, so `Photo` was a model to work around that. Only a few models really depend on it.

https://thoughtbot.com/blog/closing-the-trombone

Active Storage came out and the paperclip guys themselves said that it's over. Thankfully we've already migrated the metadata over so we don't need to re-upload the files through Active Storage. The model remains however and I think that's annoying.

# Using file_upload.js

`file_upload.js` is a custom made file upload plugin, configurable through HTML attributes.

The plugin attaches to a file input's `change` event handler and copies each file selected to an editable list of hidden file inputs.

It was developed with `repositories/_form.html.erb` in mind, however I tried my best to make it generic. Repositories has photos attached via a `accepts_nested_attributes_for` for historic reasons. **You can use any column name as a straight-forward POST form upload**

## Basic usage

The plugin depends on an file input element and a preview div element. `file_upload` specific attributes are prefixed with `data-file-upload-*`. Regular standard input element attributes still apply and function, such as `accept`, `placeholder`, and `multiple`.

```erb
<%= file_field_tag 'repository[photos_attributes]',
    type: :files,
    multiple: true,
    data: {
        file_upload_helper: true,
        file_upload_preview_selector: '[data-file-upload-preview]',
        file_upload_limit: 5,
        }  %>

```

`data-file-upload-helper` marks the element for pickup by the plugin on document load (on `turbo:load`, to be specific).

`data-file-upload-preview-selector` specifies the selector to find the preview pane. This can be any `querySelector` compatible string. Only one preview pane can be attached to the input element. The first matching element will be used. I recommend using a data attribute to imply it's uniqueness.

`data-file-upload-limit` limits the number of files allowed by the input file. Any files selected that go over the limit will silently be ignored. If you're allowing multiple file uploads then I recommend you set `multiple` as well. By default no limit is enforced.

`name` is copied from the main input element and appended to the name of each
