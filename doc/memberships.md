# Makerepo Memberships

We're making people pay now. People can buy a one day, 30 day, or 1 semester
long membership via a shopify draft order. As usual we have a confusing and
rushed naming scheme. Users can get a membership through:

- Shopify draft order, or
- Tapping their cards on a tap box, then we query uOCampus via uOEng.

People can buy a day-long, a month-long, or a semester-long membership.
Membership status is displayed on user profiles and staff dashboards.

## uOEngineering queries

We managed to trick admin to give us access to protected data, yippee. Rule is
to **never display student name and student ID together.** Don't display emails
anyways since that would invite spam crawlers.

The API calls are defined in the `user/uoeng_concern.rb` concern. The concern is
used by the `RfidController` to query if a user is eligible for a semester-long
faculty membership when they tap into a space. See the tapbox documentation for
more information on how the RFID card system works
