# Job Orders Overview

## Core Tables

- **job_orders:** Parent table of all job order (jo)
- **job_tasks:** A job order is comprised of tasks that detail a single service with options and files
- **chat_messages:** client and staff communication

## Key Files

- **Controllers**
  - `JobOrdersController`: handle quoting and CRUD of job order stuff
  - `JobTasksController`: handle CRUD of tasks
  - `ChatMessageController`: handle basic chat stuff

The /job_orders/:id page handles everything to do with a specific job order for clients and staff.

Project files (user and staff) are now stored in job tasks meaning the job order model can be purged of files and user_comments.

## Quotes and pricing

Job options are tacked onto a job order to create a complete invoice. `JobOptions` describe the possible options, then `JobOrderOptions` are created for each option added to a job order

An job type is a big thing you want to do, like laser cut or 3d print or a design service. Big changes.

A job option is a

A job order has a job type.
A job type owns job services

job type has many job options.

service fee is a flat this costs for a human to do it
