# Making Changes

## Hotfixes

Hotfixes are rare but sometimes necessary. In the case of broken core functionality of the site, it is important to restore operations as soon as possible. Scenarios that qualify as necessary for hotfixes include bugs causing degraded service of cores features, issues that intefere with the general public interacting with the site and so on.

Core features might include: - Authentication Services (Login, SAML) - Staff Kiosk - Project Proposals - Repositories

### The Process:

- [ ] (Optional) Enable maintence mode with cap production maintenance:enable REASON="Immediate Unexpected Maintenance" UNTIL="HH:MM (H:MM AM/PM)"
- [ ] Create a new branch from master.
- [ ] Make the necessary fix.
- [ ] Include "[skip actions]" in your commit message to avoid redundant CI runs.
- [ ] Open a Pull Request
- [ ] If feasible, have someone review the PR. If not, do a self review.
- [ ] Merge into master
- [ ] Monitor the workflow run from the actions tab.
- [ ] cap production maintenance:disable

### Important Notes:

- Use maintenance mode if users can reasonably be expected to encounter errors.
- Skipping CI will allow you to merge earlier, the workflow to deploy to production runs rspec.
- Open a pull request instead of pushing straight to master, this gives you a second chance to review the changes and is easier to manage.

## Bug Fixing

When a bug is identified but not in need of hotfixing, there are two avenues that could be taken. Ideally, you will use staging to verify the bug has been fixed and allow affected parties to verify it was fixed in the appropriate manner. However, if staging is tied up with another feature that may not be ready for production soon enough, it may be acceptable to move straight to production with the fix. There are no set criteria but things to keep in mind are the complexity of the fix and whether it has the chance to create unintended side effects.

### The Process:

- [ ] Create or assign yourself to an existing issue.
  - [ ] If reported by a third party, ensure you have a complete understanding of what the issue is.
- [ ] Create a new branch from master or staging.
- [ ] Make the necessary fix.
- [ ] Include a descriptive commit message.
- [ ] Open a Pull Request
- [ ] Await review of the Pull Request.
  - [ ] Make necessary changes and request another review.
- [ ] Merge into staging.
- [ ] Verify the fix on staging. If issue was reported by a third party, have them verify it is corrected on staging.
- [ ] Open a Pull Request for Master
- [ ] Await review and merge.

### Important Notes

If staging is occupied and the bug fix is relatively simple (a single line change, design change, etc) then you can skip staging and open a PR directly for Master.

## New Features

New features should never be put on production without going through staging first. To minimize comingling and ensuring ease of cherry-picking commits if necessary, two features should never be on staging simulatenously, there should only be a new feature and optionally low priority bug fixes.

### The Process

- [ ] Create or assign yourself to an existing issue.
- [ ] Consult with stakeholders to develop requirements for the new feature.
- [ ] Review plan to add new feature, which models, controllers, views are necessary, what business logic should be implemented.
  - [ ] (Optional) Review existing similar features to keep code and implementation details consistent.
- [ ] Create a new branch from staging.
- [ ] Implement the new features
- [ ] Create tests covering aspects of the new feature.
- [ ] Open a Pull Request
- [ ] Await review of the Pull Request.
  - [ ] Make necessary changes and request another review.
- [ ] Merge into staging.
- [ ] Get stakeholders to verify the new feature on Staging, ask for feedback
  - [ ] Checkout feature branch
  - [ ] Implement requested changes from stakeholders
  - [ ] Open a pull request for feature branch to staging
  - [ ] Repeat
- [ ] Open a Pull Request for Master
- [ ] Await review and merge.
- [ ] (Optional) Create announcement about the new feature if it is significant and public facing.
