# New developer guide

The goal of this guide is to quickly describe the various systems and subsystems we operate at CEED.

For information about the servers, consult internal documentation. When writing documentation, try to keep only technical information here and avoid committing administrative information.

Generate a key pair and add to all servers

https://wiki.archlinux.org/title/SSH_keys

# Collaborating in a team

We're assuming you know how to use git. If not, the ![Pro Git book](https://git-scm.com/book/en/v2) is an incredibly useful resource. I'd love for you to read the whole thing, it's quite short. Nevertheless chapters 1, 2, and 3 cover the basics.

When making a Github account, use an account you want to show off. Makerepo is public and open source and using your personal account is a good resume booster too.

## Adding to zenhub

Go to the switch workspace panel, click on the organization name, manage organization, then users, then invite and assign licenses to user. We get 10 licensed users, boot out the old devs and put the new ones in.

## SSH keys

Github won't allow you to push without setting up a key. Keep the private part private, only give out the file ending with `.pub`

https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account

## Configuring git line ending handling

If you're on windows, then every file you touch might have it's line endings overwritten. This ruins file history, makes it harder to do code review, and would cause merge conflicts with developers on other operating systems.

We use `LF` line endings. Git should be automatically configured to enforce `LF` line endings. If it is not configured to do so, follow the instructions on this page:

https://docs.github.com/en/get-started/git-basics/configuring-git-to-handle-line-endings

For a better explanation, this article puts it better: https://adaptivepatchwork.com/2012/03/01/mind-the-end-of-your-line/

## Commit hooks

When commiting to a local branch, a commit hook runs. The script is found in `.husky/pre-commit`.

1. It runs a formatter on all staged code
2. Pulls in code from the remote branch
3. Re-stages formatted code

During this phase if you're not connected to the internet the commit hook might fail. Just comment out the `git fetch` part, i'll fix it later :^).

# Developing a new feature

New feature development is fun: you get quick results while developing and features are instantly used by users. However it's rather easy to get carried away with it and forget about the boring stuff, like tests and documentation

## Research previous solutions

Ruby on Rails is very flexible with what is possible, but very rigid in how to implement what is possible. For basic CRUD, the ![Getting starting with Rails](https://guides.rubyonrails.org/getting_started.html#creating-a-database-model) guide pretty much describes the entire development process from start to finish.

The framework is very extensive and it doesn't hurt to search for built-in solutions. The goal here is to make something that reliable, not novel. Be careful when installing new rails gems or dependencies because often they don't survive stack upgrades and get left behind.

Similarly for frontend design, always prefer to use the frameworks already installed. We have Bootstrap 5 installed. It is a complete CSS framework solution and provides a consistent look and feel for the many UI components used across the website. If you have to do something with CSS, Bootstrap already has it covered.

See more links here:

- https://guides.rubyonrails.org/
- https://api.rubyonrails.org/ (a bit harder to use, be wary of the Rails version displayed)
- https://getbootstrap.com/docs/5.3/layout/columns/
- https://getbootstrap.com/docs/5.3/forms/overview/

## Write and finalize specifications before starting

Before writing any code, make sure that you know exactly what you need to do and what you need to avoid. This "design document" could later on be rewritten with implementation details and converted into a complete documentation page.

A good example is `doc/payments.md`. This document describes what a reusable part of the website does and how it interacts with external services.

The current codebase has a lot of incrementally added patches that degrade code quality and make future maintenance harder. Try to avoid falling into that cycle, and if you find yourself patching your branch over and over then a design overview might be due.

## Development cycle

Make a separate branch and commit changes to it. Once all functionality is there, tests pass, and documentation is complete create a pull request to the staging branch.

Some rules to abide by:

- Don't force-push to master or staging. Force-pushing overwrites commits and might delete code other developers are using. Always resolve merge conflicts.
- Don't skip CI/CD. Tests are important and if they fail then that's something you should fix. Deployments only happen when CI finished successfully too.
- Branch of staging branch, test locally, then merge back into staging branch. Create a pull request and have someone else look over the code.
- Make small commits. Write actual descriptive commit messages. They help to explain your decisions and when investigating bugs.

# How to make a feature

Ruby on Rails implements the MVC model. This is the most common development model for web servers. Our stack is very simple: postgres database and Vite for static content.

Now I'd tell you to look and learn from what code already exists, but there's a lot of stuff I'm not proud of in there. Prime example of cargo-cult programming. If in doubt, consult the framework docs.

## Controller

Controllers provide methods called by defined routes. The controller is responsible for handing permissions and authentication, and parsing parameters sent by users. This part is often slim and doesn't have much going on. Use `before_action` macros to control access.

Admin controllers inherit from `AdminAreaController` and are placed in `app/controllers/admin/`. This base controller ensures current users are logged in and are admins.

Staff controllers inherit from `StaffAreaController` and ensure that the current user is logged in as a staff member.

The home page controller is a good example. It shows simple data queried from multiple models.

Controllers can also expose API endpoints. The tap boxes used around CEED spaces contact makerepo RFID controllers to register users logging in. The design day website (eventually) also contacts makerepo REST endpoints and receives a JSON response.

## Model

The model is where business logic lives. All interactions with the database should happen through the model layer. Models are put in `app/models` and inherit from `ApplicationRecord` (an alias for `ActiveRecord::Base`).

The model class name needs to match the table name. The details are Rails provides generators to make new tables and models with the right names and locations. Refer to the official guide for more important information

Active Record provides generic DB commands, and the subclass should contain specialized methods to handle common operations. Controllers later call these methods with a set of parameters.

A good example is `app/models/locker_rental.rb`. It shows a good example of automatically managing email notification and preventing incomplete locker rentals. It also gives an example of how concerns are used to share common functionality across the website.

Active Record validations are used to ensure that invalid data never gets written to disk. Controllers are responsible for ensuring users can access the data. Model validations are responsible for making sure the data is correct.

I like using concerns when modelling API calls to other services. The `ShopifyConcern` concern is used for locker rentals and job orders, and helps to make interactions consistent and testable across the entire website. Another example of concerns is the `CredlyConcern` used in badges. They integrate external API calls transparently into models, while keeping business logic in the model layer.

- https://guides.rubyonrails.org/active_record_migrations.html : Making a new table
- https://guides.rubyonrails.org/active_record_basics.html : interacting with the database
- https://guides.rubyonrails.org/active_model_basics.html : common helper methods provided by rails
- https://guides.rubyonrails.org/active_record_validations.html : How to return form errors
- https://www.writesoftwarewell.com/how-rails-concerns-work-and-how-to-use-them/

## View

The view super complicated tbh. ERB templates, form helpers, layouts and response formats. Localization and keys, what is YAML

JS scripts are nice but tend to be kept for admin and staff side pages. Users are often students and we have an obligation to keep the pages as accessible as possible. Use semantic HTML tags and minimal scripting. Images should be compressed JPEGs. Layouts must be mobile responsive and tested on multiple screens.

We use a couple javascript plugins. Prefer progressive enhancement, where the website is still usable even when javascript is disabled

# What happens after development

- Pushing to a remote branch triggers CI tests
- Pushing to staging triggers CI tests, then if successful deploys to staging server.
- Pushing to master triggers CI tests, then if successful deploys to production server.

Never push to master directly, or at least don't consider it as a good option.

# How to write unit tests

Unit tests are a way to ensure behavior does not change unexpectedly.

- What is rspec
- How to use rspec
- when does it run
