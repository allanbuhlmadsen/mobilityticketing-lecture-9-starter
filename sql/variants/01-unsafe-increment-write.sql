-- Variant of sql/unsafe-write.sql for the constraint experiment in task 1.
-- The decision still lives in the session variables, but the counter is now
-- incremented from the row's current value instead of the stale reading.
-- There is deliberately no capacity condition in the WHERE clause.
\if :can_book
UPDATE lab09.trips
SET reserved_seats = reserved_seats + 1
WHERE id = :'trip_id';

INSERT INTO lab09.bookings (request_id, passenger_id, trip_id)
VALUES (:'request_id', :'passenger_id', :'trip_id')
RETURNING id;
\else
\echo The read found no available seat. No booking was written.
\endif