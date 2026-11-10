-- Final implementation of lab09.book.
--
-- The function runs inside the caller's transaction and never commits.
--
-- Two separate problems, two mechanisms:
--
--   Capacity   an explicit row lock on the trip, taken before availability is
--              read, so the decision cannot go stale between reading and
--              writing. Chosen over the alternatives compared in
--              docs/evidence.md because it waits only for the trip in question
--              and keeps the row in hand, which is what allows a rejection to
--              say why.
--
--   Repeated   a lookup on request_id before anything is locked or changed, so
--   requests   a replay costs neither a lock nor a seat and can answer even
--              after the trip has filled up or been cancelled. The unique
--              constraint on request_id is the backstop for two identical
--              requests that arrive at the same moment and cannot see each
--              other's uncommitted rows.

CREATE OR REPLACE FUNCTION lab09.book(
    p_request_id text,
    p_passenger_id text,
    p_trip_id text
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing   lab09.bookings;
    v_trip       lab09.trips;
    v_booking_id bigint;
BEGIN
    -- A request we have already stored is answered from the booking itself.
    SELECT * INTO v_existing
      FROM lab09.bookings
     WHERE request_id = p_request_id;

    IF FOUND THEN
        IF v_existing.passenger_id <> p_passenger_id
           OR v_existing.trip_id <> p_trip_id THEN
            RAISE EXCEPTION
                'Request % belongs to passenger % on trip %, not to passenger % on trip %',
                p_request_id, v_existing.passenger_id, v_existing.trip_id,
                p_passenger_id, p_trip_id;
        END IF;
        RETURN v_existing.id;
    END IF;

    -- Both writes live inside this block, so that a unique violation on
    -- request_id undoes the counter change together with the insert.
    BEGIN
        SELECT * INTO v_trip
          FROM lab09.trips
         WHERE id = p_trip_id
           FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No seat reserved for trip %: it does not exist', p_trip_id;
        END IF;

        IF v_trip.status <> 'Scheduled' THEN
            RAISE EXCEPTION 'No seat reserved for trip %: it is %', p_trip_id, v_trip.status;
        END IF;

        IF v_trip.reserved_seats >= v_trip.capacity THEN
            RAISE EXCEPTION 'No seat reserved for trip %: the trip is full', p_trip_id;
        END IF;

        UPDATE lab09.trips
           SET reserved_seats = reserved_seats + 1
         WHERE id = p_trip_id;

        INSERT INTO lab09.bookings (request_id, passenger_id, trip_id)
        VALUES (p_request_id, p_passenger_id, p_trip_id)
        RETURNING id INTO v_booking_id;

        RETURN v_booking_id;

    EXCEPTION WHEN unique_violation THEN
        -- Another transaction committed this very request while we were
        -- working. Everything this block did is now undone, the counter
        -- increment included, so the stored booking is the only one.
        SELECT * INTO v_existing
          FROM lab09.bookings
         WHERE request_id = p_request_id;

        IF NOT FOUND THEN
            RAISE;
        END IF;

        IF v_existing.passenger_id <> p_passenger_id
           OR v_existing.trip_id <> p_trip_id THEN
            RAISE EXCEPTION
                'Request % belongs to passenger % on trip %, not to passenger % on trip %',
                p_request_id, v_existing.passenger_id, v_existing.trip_id,
                p_passenger_id, p_trip_id;
        END IF;

        RETURN v_existing.id;
    END;
END;
$$;