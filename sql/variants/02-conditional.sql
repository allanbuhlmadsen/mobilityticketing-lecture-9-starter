-- Task 2: the conditional update. The UPDATE itself decides whether a seat
-- is available; nothing is read beforehand. Request-ID handling comes in task 6.
-- The function runs in the caller's transaction; it does not COMMIT.
CREATE OR REPLACE FUNCTION lab09.book(
    p_request_id text,
    p_passenger_id text,
    p_trip_id text
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_reserved integer;
    v_booking_id bigint;
BEGIN
    UPDATE lab09.trips
       SET reserved_seats = reserved_seats + 1
     WHERE id = p_trip_id
       AND status = 'Scheduled'
       AND reserved_seats < capacity
    RETURNING reserved_seats INTO v_reserved;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No seat reserved for trip %: missing, cancelled or full', p_trip_id;
    END IF;

    INSERT INTO lab09.bookings (request_id, passenger_id, trip_id)
    VALUES (p_request_id, p_passenger_id, p_trip_id)
    RETURNING id INTO v_booking_id;

    RETURN v_booking_id;
END;
$$;