-- The optimistic check.
--
-- No lock is taken and nobody is told to wait. The function reads
-- reserved_seats in a statement of its own, then updates only while the
-- counter still holds the value that read returned. A change committed by
-- somebody else in between turns the update into zero rows instead of letting
-- it overwrite, which is exactly the overwrite that task 1 could not detect.

CREATE OR REPLACE FUNCTION lab09.book(
    p_request_id text,
    p_passenger_id text,
    p_trip_id text
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_observed   integer;
    v_reserved   integer;
    v_booking_id bigint;
BEGIN
    SELECT reserved_seats
      INTO v_observed
      FROM lab09.trips
     WHERE id = p_trip_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No seat reserved for trip %: it does not exist', p_trip_id;
    END IF;

    UPDATE lab09.trips
       SET reserved_seats = reserved_seats + 1
     WHERE id = p_trip_id
       AND status = 'Scheduled'
       AND reserved_seats < capacity
       AND reserved_seats = v_observed
    RETURNING reserved_seats INTO v_reserved;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Optimistic check failed for trip %: it is cancelled, it is full, or reserved_seats is no longer %',
            p_trip_id, v_observed;
    END IF;

    INSERT INTO lab09.bookings (request_id, passenger_id, trip_id)
    VALUES (p_request_id, p_passenger_id, p_trip_id)
    RETURNING id INTO v_booking_id;

    RETURN v_booking_id;
END;
$$;