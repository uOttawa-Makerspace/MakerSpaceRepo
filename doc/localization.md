# YAML all the way

[Read this](https://guides.rubyonrails.org/i18n.html) then continue with this document. This is just a very brief and incomplete summary of the actual docs.

Make sure to always localize text. They're in `config/locales` and should contain all text in the website. For smallish pages it's okay to keep both languages in a file, but for longer files it's better to split them off for easier debugging and cleaner edit history tracking. The project is setup to (recursively?) load all yaml files and merge them.

Localization is just putting text in a YAML file, a subset of JSON. Getting a localized key is like accessing a hash, you might receive a string, an array, or another hash. You can put HTML in there, call `.html_safe` on the string. Keys that end with `_html` are automatically marked html safe and not escaped. You can also put links, to send users to the french or english version of a page (university website for example).

You can use regular YAML structures. Lists for bullet points are okay. Don't overdo them, other people changing the text after you're gone should not risk a runtime error. You're localizing static text that doesn't change much after it's published. Don't encode the entire page into a B Tree.

If you don't speak french or english, at least put the text in a locale file for someone else to do it after you.

For massive bodies of text, consider localized views instead. Partials that end with `<locale_code>.html.erb` are automatically loaded.

**Always test both languages** The automated tests run on english locale only, somewhat unforunately. If you ever touch a locale file, verify both languages work and don't return any errors
I think `I18n.current_locale` may be broken in rspec tests, it seems to always return `:en`. Might be a bug with the framework, however it would be better to avoid using `I18n.current_locale` in controllers and model functions and instead receive them as arguments.

## Quick explainer

All YAML files are loaded and merged as one file, with the top level prefix key being the locale code. So for users on french locale, all recalled keys are under the 'fr' top level key. Both locale files must have identical structure for the localization to properly work: imagine Rails prefixing the locale before each key.
Keys prefixed with `_html` are automatically marked as html safe. This means you can put html tags inside locale strings. In the the volunteers page, every occurrence of the word CEED is wrapped in an orange span. Don't put an excessive amount of html into a locale string, if you need more than one you probably should split them into two strings instead.
