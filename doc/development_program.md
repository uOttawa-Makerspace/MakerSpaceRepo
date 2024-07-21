# MAN WHAT THE FUCK

Development program is buggy as hell

The volunteer program is fine i guess.

## Development program basics

Built around awarding badges to projects and learning tracks. Badges are tracked by a service called Credly (previously called acclaim, that's what it's called in the code base).

The docs are actually nice

- https://www.credly.com/docs/web_service_api
- https://www.credly.com/docs/badge_templates

Students complete learning modules to gain basic badges, then create and submit proficiency project requests. Staff look at requests and approve them.

Badges are based on three tables, the `badges` table and the `badge_templates` and the `certifications` table
`badge_templates` contains

## ERROR

An error has occurred when creating the badge, this message might help : Invalid or missing Badge Template ID: d56b6e25-772b-48b1-a40e-b954b07c734d

## Development/Volunteer program redesign

Badges and skills are lifted from the user profile page
Skills are certifications? **Limit the count of skills**, some have a lot of skills. Display level not number
We do track development program progress, it is the number of modules completed. Skills are just the level achieved

All badges have a skill, not all skills have a badge associated. There should be one for every but we didn't create enough badges. Someone might have a skill with no badge to show for it :(.

Vector graphics is NOT a workshop we give, but it is a skill in the development program. No badge for it too.

Basic java is a workshop, shown in the list because when after the workshop we give certification. No learning module, no proficiency project, etc. for it.

Development program has learning modules:
green number is beginner, yellow is intermediate. not much learning modules :^).
People should look at all the learning modules, do a proficiency project, then get a badge for it. That'

Think of a way to clean up or clearly explain all of this. Maybe change terminology or link paths.
There isn't a corresponding project/badge/workshop for all skills, make that clear somehow...

Maybe make a summary project? Step one was learning modules, step two was the projects, step three was the badges.

You can be in progress of a development program skill, but not in progress in a workshop session. Skills should only display level instead.
