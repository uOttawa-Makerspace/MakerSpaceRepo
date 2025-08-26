# Makerepo Memberships

We're making people pay now. People can buy a one day, 30 day, or 1 semester
long membership via a shopify draft order. As usual we have a confusing and
rushed naming scheme. Users can get a membership through:

- Shopify draft order, or
- Tapping their cards on a tap box, then we query uOCampus via uOEng.

# uOEngineering queries

We managed to trick admin to give us access to protected data, yippee. Rule is
to **never display student name and student ID together.** Don't display emails
anyways since that would invite spam crawlers.

For now we query the details on the spot, and if we determine a user is paying
the fee we create a semester long membership.
