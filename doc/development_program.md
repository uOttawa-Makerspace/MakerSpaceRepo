Development program is buggy as hell

The volunteer program is fine i guess.

## Development program basics

Built around awarding badges to projects and learning tracks. Badges are tracked by a service called Credly (previously called acclaim, that's what it's called in the code base).

The docs are not bad:

- https://www.credly.com/docs/web_service_api
- https://www.credly.com/docs/badge_templates

Students complete learning modules to gain basic badges, then create and submit proficiency project requests. Staff look at requests and approve them.

Badges are based on three tables, the `badges` table and the `badge_templates` and the `certifications` table. `badge_templates` contains the acclaim template ID.

Badge templates point to a training skill and level.
Badges themselves store a badge template ID and an acclaim badge ID. The badge template ID refers to a local badge template, which in turn refers to a remote badge template. The acclaim badge ID refers to the remote badge ID.

Project approval requests are stored as `OrderItems`. To get approved ones do `@repo_user.order_items.awarded.pluck(:proficient_project_id)`

## Production badge apis as of Mon Jul 22 15:11:12 2024

[["Shop Fundamentals || Principes fondamentaux de l’atelier d’usinage", "7fc522fa-0044-4a0e-a716-90b808260e6b"],
["Beginner - Mill || Débutant - Fraiseuse", "6ecc14a7-265a-45bf-918d-ffdf5100f4b4"],
["Beginner - Lathe || Débutant - Tour", "30e1b3ab-344c-4938-9236-5a03101b95a7"],
["Beginner - MIG Welding || Débutant - Soudure", "a72405e1-46d5-4b8b-b216-98fc362d599b"],
["Beginner - 3D printing || Débutant - Impression 3D", "79135bb6-a371-4871-853c-3e41f1724147"],
["Beginner Laser cutting || Beginner - Laser cutting", "37a17118-9be4-438a-b012-a575f9d06a71"],
["Beginner - Arduino || Débutant - Arduino", "d56b6e25-772b-48b1-a40e-b954b07c734d"],
["Beginner - Soldering || Débutant – Soudure électrique", "ae2e68fc-404f-4a2f-9d34-e420aca5230a"],
["Beginner - Embroidery || Débutant - Broderie", "86de7d36-cfed-4a3e-8998-fd7da1aee753"],
["Beginner - Virtual Reality || Débutant - Réalité Virtuelle", "7b123b16-579d-4524-ac18-a0822973522a"],
["Professional Development || Développement professionnel", "61edc16e-5fd0-402c-9c71-b96e7e27a3fb"],
["Accessibility Make-a-thon || Accessibilité Make-a-thon", "a7fd74d9-56ba-4d33-b783-a0391bd11ab5"],
["Simon Nehme Summer Entrepreneurship School", "1e91c9df-ff64-4cae-b298-b17e60869e18"],
["Beginner - TIG Welding || Débutant - Soudure TIG", "ca22b099-6986-4400-9892-df9a5288163b"],
["Beginner - 3D printing (resin) || Débutant - Impression 3D (résine)", "8ebd943f-baff-40c7-9cbb-fca2161064a6"],
["Beginner - 3D scanning || Débutant - Numérisation 3D", "2aaf4070-5461-4fef-953a-1a3f8ebfceb2"],
["Beginner - PCB Design || Débutant - Conception PCB", "404eb116-87e9-450a-99bd-c462a9823bc6"],
["Beginner - PCB Milling || Débutant - Fraisage PCB", "bb739952-bf54-4644-bf4f-290301e2982d"]]

## Training sessions

People take a training session first. Staff create a training session from the dashboard, add attendees. They then click certify after they're done. Exams exist but IDK if anyone uses them really.
Note that the service might sometimes fail, because of downtime or issuing duplicate badges. Whatever the case, if the service doesn't return a 201 Created, we assume failure. Badges can be granted manually anyways, but we don't want to fail the project just because credly says so.

## The sandbox sucks

https://credlyissuer.zendesk.com/hc/en-us/articles/360027660512-Is-there-a-sandbox-staging-site-where-we-can-test-integrations
Credly has a sandbox, which contains only three badges. It has separate data from production and different template IDs and such, so testing badge success is difficult on a development environment. I'm not sure if there's a way to set the template ID for a badge manually.

You might see this message when working with training sessions:

> An error has occurred when creating the badge, this message might help : Invalid or missing Badge Template ID: d56b6e25-772b-48b1-a40e-b954b07c734d
> Search the logs for this error too, try to catch the code it returns when issuing duplicate badges.

## Development/Volunteer program redesign

Badges and skills are displayed on the user profile page, they also show proficient projects done and 'hours' needed to continue to next level.
Skills are certifications? **Limit the count of skills when displaying them**, some have a lot of skills. Display level not number
We do track development program progress, it is the number of modules completed. Skills are just the level achieved

All badges have a skill, not all skills have a badge associated. There should be one for every but we didn't create enough badges. Someone might have a skill with no badge to show for it :(.

Vector graphics is NOT a workshop we give, but it is a skill in the development program. No badge for it too.

Basic java is a workshop, shown in the list because when after the workshop we give certification. No learning module, no proficiency project, etc. for it.

Development program has learning modules:
green number is beginner, yellow is intermediate. not much learning modules :^). Note that these might have broken views.
People should look at all the learning modules, do a proficiency project, then get a badge for it.

Think of a way to clean up or clearly explain all of this. Maybe change terminology or link paths.
There isn't a corresponding project/badge/workshop for all skills, make that clear somehow...

Maybe make a summary project? Step one was learning modules, step two was the projects, step three was the badges.

You can be in progress of a development program skill, but not in progress in a workshop session. Skills should only display level instead.
