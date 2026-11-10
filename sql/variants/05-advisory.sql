-- Task 3, version 3: a transaction advisory lock.
-- The task prescribes namespace 9009 and the keys T-LAST = 1, T-TWO = 2,
-- T-CANCELLED = 3, T-OTHER = 4. The mapping lives in one function so that
-- every cooperating booking path can use the same one.
CREATE OR REPLACE FUNCTION lab09.trip_lock_key(p_trip_id text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_trip_id
               WHEN 'T-LAST'      THEN 1
               WHEN 'T-TWO'       THEN 2
               WHEN 'T-CANCELLED' THEN 3
               WHEN 'T-OTHER'     THEN 4
           END;
$$;

CREATE OR REPLACE FUNCTION lab09.book(
    p_request_id text,
    p_passenger_id text,
    p_trip_id text
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_key integer;
    v_trip lab09.trips%ROWTYPE;
    v_booking_id bigint;
BEGIN
    v_key := lab09.trip_lock_key(p_trip_id);
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'No seat reserved for trip %: no advisory lock key is defined for it', p_trip_id;
    END IF;

    PERFORM pg_advisory_xact_lock(9009, v_key);

    SELECT * INTO v_trip
      FROM lab09.trips
     WHERE id = p_trip_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No seat reserved for trip %: the trip does not exist', p_trip_id;
    END IF;

    IF v_trip.status <> 'Scheduled' THEN
        RAISE EXCEPTION 'No seat reserved for trip %: the trip is %', p_trip_id, v_trip.status;
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
END;
$$;