-- Task 3, version 2: a table lock. The whole trips table is locked before
-- anything is read, so no other session can change any trip meanwhile.
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
    v_trip lab09.trips%ROWTYPE;
    v_booking_id bigint;
BEGIN
    LOCK TABLE lab09.trips IN EXCLUSIVE MODE;

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