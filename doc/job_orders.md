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
