-- The current year of study of every user, counted from the reference point
-- (year_of_study_entered, year_of_study_set_on) the same way as
-- User::YearOfStudy#current_year_of_study: a student moves up one year on the
-- first day of the month the account was created in (Toronto time), every year
-- after the year it was created, up to year 8, then Alumni. Read only.
SELECT users.id AS user_id,
  CASE
    WHEN moves.n = 0 OR users.year_of_study_entered IS NULL OR users.year_of_study_entered = 'Alumni'
      THEN users.year_of_study_entered
    WHEN entered.year BETWEEN 1 AND 7 AND entered.year + moves.n <= 8 THEN (entered.year + moves.n)::text
    ELSE 'Alumni'
  END AS year_of_study,
  users.year_of_study_entered,
  users.year_of_study_set_on,
  users.year_of_study_set_by
FROM users
CROSS JOIN LATERAL (
  SELECT (users.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York' AS created,
         (now() AT TIME ZONE 'America/New_York')::date AS today
) here
CROSS JOIN LATERAL (
  SELECT CASE WHEN users.identity IN ('grad', 'undergrad', 'international_grad', 'international_undergrad') THEN GREATEST(0,
    EXTRACT(YEAR FROM here.today)::int
      - CASE WHEN EXTRACT(MONTH FROM here.created) > EXTRACT(MONTH FROM here.today) THEN 1 ELSE 0 END
      - GREATEST(
          EXTRACT(YEAR FROM users.year_of_study_set_on)::int
            + CASE WHEN EXTRACT(MONTH FROM here.created) > EXTRACT(MONTH FROM users.year_of_study_set_on) THEN 0 ELSE 1 END,
          EXTRACT(YEAR FROM here.created)::int + 1)
      + 1)
  ELSE 0 END AS n
) moves
CROSS JOIN LATERAL (
  SELECT COALESCE(substring(users.year_of_study_entered FROM '^[0-9]+')::numeric, 0) AS year
) entered
