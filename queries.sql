---counts the number of Trips more than 2 seats booked
SELECT COUNT(*) AS number_of_trips
FROM flights
WHERE seats > 2;
---select origin of where return flights booked
SELECT trip_id, origin_airport, destination, departure_time, return_time
FROM flights
WHERE return_flight_booked IS TRUE;
---calculates the average number of checked bags that have return flight booked
SELECT AVG(checked_bags) AS average_checked_bags
FROM flights
WHERE return_flight_booked IS TRUE;
---Trips where exactly 2seats where booked and no check in Bags were added
SELECT trip_id, origin_airport, destination, departure_time
FROM flights
WHERE seats = 2 AND checked_bags = 0;
---calculates the total cost of each of hotel stay night per discount
SELECT trip_id, hotel_name,
       rooms * nights * hotel_per_room_usd AS total_cost_usd
FROM hotels;
---find the amount of Hotel stays longer than 7nights
SELECT trip_id, hotel_name, nights, check_in_time, check_out_time
FROM hotels
WHERE nights > 7;
--the total number of hotel room booked for all hotel brand
SELECT hotel_name, SUM(rooms) AS total_rooms_booked
FROM hotels
GROUP BY hotel_name;
---all hotel stays where check in is Year 2024
SELECT trip_id, hotel_name, check_in_time, check_out_time
FROM hotels
WHERE EXTRACT(YEAR FROM check_in_time) = 2024;
---The Cohort query after January 2023
-- This CTE prelimits our sessions on Elena's suggested timeframe (After Jan 4 2023)
WITH sessions_2023 AS (
  SELECT *
  FROM sessions s
  WHERE s.session_start > '2023-01-04'
),
-- This CTE returns the ids of all users with more than 7 sessions in 2023
filtered_users AS (
  SELECT user_id,
               COUNT(*)
  FROM sessions_2023 s
  GROUP BY user_id
  HAVING COUNT(*) > 7
),
session_base AS (
 SELECT
          s.session_id,
          s.user_id,
          s.trip_id,
          s.session_start,
          s.session_end,
          s.page_clicks,
          s.flight_discount,
          s.flight_discount_amount,
          s.hotel_discount,
          s.hotel_discount_amount,
          s.flight_booked,
          CASE
              WHEN s.flight_booked = 'yes' THEN 1
              ELSE 0
          END AS flight_booked_int,
          s.hotel_booked,
          CASE
              WHEN s.hotel_booked = 'yes' THEN 1
              ELSE 0
          END AS hotel_booked_int,
          s.cancellation,
          CASE
              WHEN s.cancellation = 'yes' THEN 1
              ELSE 0
          END AS cancellation_int,
             u.birthdate,
          u.gender,
          u.married,
          u.has_children,
          u.home_country,
          u.home_city,
          u.home_airport,
          u.home_airport_lat,
          u.home_airport_lon,
          u.sign_up_date,
             f.origin_airport,
          f.destination,
          f.destination_airport,
          f.seats,
          f.return_flight_booked,
          f.departure_time,
          f.return_time,
          f.checked_bags,
          f.trip_airline,
          f.destination_airport_lat,
          f.destination_airport_lon,
          f.base_fare_usd,
             h.hotel_name,
          CASE
              WHEN h.nights < 0 THEN 1
              ELSE h.nights
          END AS nights,
          h.rooms,
          h.check_in_time,
          h.check_out_time,
          h.hotel_per_room_usd AS hotel_price_per_room_night_usd
  FROM sessions_2023 s
  LEFT JOIN users u
        ON s.user_id = u.user_id
    LEFT JOIN flights f
        ON s.trip_id = f.trip_id
    LEFT JOIN hotels h
        ON s.trip_id = h.trip_id
  WHERE s.user_id IN (SELECT user_id FROM filtered_users)
),
-- This CTE returns the ids of all trips that have been canceled through a session
-- We use this list to filter all canceled sessions in the next CTE
canceled_trips AS (
  SELECT DISTINCT trip_id
  FROM session_base
  WHERE cancellation = TRUE
),
-- This is our second base table to aggregate later
-- It is derived from our session_base table, but we focus on valid trips
-- All sessions without trips, all canceled trips have been removed
-- Each row represents a trip that a user did
not_canceled_trips AS(
  SELECT *
  FROM session_base
    WHERE trip_id IS NOT NULL
    AND trip_id NOT IN (SELECT trip_id FROM canceled_trips)
),
-- We want to aggregate user behaviour into metrics (a row per user)
-- This CTE contains metrics that have to do with the browsing behaviour
-- ALL SESSION within our cohort get aggregated
user_base_session AS(
        SELECT user_id,
      SUM(page_clicks) AS num_clicks,
      COUNT(DISTINCT session_id) AS num_sessions,
      AVG(session_start - session_end) AS avg_session_duration
FROM session_base
GROUP BY user_id
),
-- We want to aggregate user behaviour into metrics (a row per user)
-- This CTE contains metrics that have to do with the travel behavious
-- Only rows with VALID trips within our cohort get aggregated
    user_base_trip AS(
    SELECT     user_id,
                     COUNT(DISTINCT trip_id) AS num_trips,
            SUM(CASE
                  WHEN (flight_booked = TRUE) AND (return_flight_booked = TRUE) THEN 2
                  WHEN flight_booked = TRUE THEN 1 ELSE 0
                END) AS num_flights,
            COALESCE((SUM((hotel_price_per_room_night_usd * nights * rooms) *
                          (1 - (CASE
                                  WHEN hotel_discount_amount IS NULL THEN 0
                                  ELSE hotel_discount_amount
                                END)))),0) AS money_spend_hotel,
            AVG(EXTRACT(DAY FROM departure_time-session_end)) AS time_after_booking,
            AVG(haversine_distance(home_airport_lat, home_airport_lon, destination_airport_lat, destination_airport_lon)) AS avg_km_flown
    FROM not_canceled_trips
        GROUP BY user_id
)
-- For our final user table, we join the session metric, trip metrics and general user information
-- Using a left join, we will get a row for each user from our original cohort codition (7+ browsing sessions in 2023)
-- If we used an inner join, we could get rid of users that have not actually travelled
SELECT b.*,
             EXTRACT(YEAR FROM AGE(u.birthdate)) AS age,
       u.gender,
       u.married,
       u.has_children,
       u.home_country,
       u.home_city,
       u.home_airport,
             t.*,
     case
         when has_children = TRUE then 'Family travelers'
         when avg_km_flown > 3000 then 'long way travelers'
         when num_flights > 5 then 'exhausted'
         else 'whatever...'
       end perks
FROM user_base_session b
    LEFT JOIN users u
        ON b.user_id = u.user_id
    LEFT JOIN user_base_trip t
        ON b.user_id = t.user_id;