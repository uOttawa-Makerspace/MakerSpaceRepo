Epic By: Valentino Vinod
Start Date: May 20th, 2025 (approximately)
End Date: August 8, 2025 (approximately)

## PURPOSE

Since CEED detached from credly we needed to host their services on makerepo itself. This epic brought:

1. Badge pages to makerepo where anybody can view a CEED-earned badge
2. Linkedin compatibility for badges
3. An overhaul to various UI elements, such as the user profile page, and the new all_badges page in dev programs

## BADGES

There are 2 ways to attain a badge:

1. Through a training session
2. Through a proficient project.

Now badges are certifications and badge_templates are trainings. The badges and badge_templates tables have been dropped. All certifications are associated with a Training either through a training_session instance or a proficient_project_session instance.

## PROFICIENT PROJECTS

A new table called proficient_project_session has been added to mimic the functioality of the training_session table. Since this altered the association between trainings and training_sessions, all certification's trainings are now accessed by a method called training() within certification.rb. Additionally, localized information such as name_en, name_fr, etc. can be accessed by various methods in certification.rb.

## TRAINING REQUIREMENTS

A join table created for the purpose of veryfying users have the necessary trainings to participate in certain prof. projects.

Requirements are fully flexible. If your Prof. Proj. gives Lathe II, you must add Lathe I as a requirement in #new.

## BADGE ICONS

We use svg to load badge icons "on the fly". See \_badge_icon.html.erb

## LINKEDIN

There's a button on badges#show if you own the badge. It takes you to linkedin and fills out all the cert information for you. Try it out. You can also download the png and add it but it doesn't look that good in my opinion. Kind of a nothing feature.
