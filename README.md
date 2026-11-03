# MobilityTicketing: Lecture 9 starter

Investigate two passengers trying to book the last seat. The
[lecture page](https://moodle.easv.dk/mod/page/view.php?id=397569)
contains the tasks. This README provides setup, the function contract and commands.

You need Docker with Compose. Clone or download this repository and run shell commands from
its root directory. Earlier labs are not required.

## Start

```sh
docker compose up -d --wait postgres
docker compose exec -T postgres bash /lab/run.sh reset
docker compose exec -T postgres bash /lab/run.sh inspect
```

The database is `mobility_l09`, with user and password `mobility`. Commands run
inside the container; no host port or local PostgreSQL installation is needed.
The image is PostgreSQL 17.

| Trip | Status | Capacity | Initial bookings |
| --- | --- | --- | --- |
| `T-LAST` | Scheduled | 1 | 0 |
| `T-TWO` | Scheduled | 2 | 0 |
| `T-CANCELLED` | Cancelled | 1 | 0 |
| `T-OTHER` | Scheduled | 2 | 0 |

`reset` recreates **only `lab09`**, clears its data and reloads your current
`sql/book.sql`. It leaves your edited files in place. End both sessions'
transactions before resetting. Save experiment output first.

## Lab tasks

Complete all eight tasks on Moodle. Use [the experiment examples](docs/experiments.md)
for session commands, SQL fragments and saving variants.

| Task | Work to keep |
| --- | --- |
| 1. Reproduce the double booking | Original sequence and increment-with-CHECK experiment |
| 2. Use a conditional update | Capacity condition, returned rows, commit and rollback runs |
| 3. Compare explicit locks | Row, table and advisory versions; different trips; deadlock |
| 4. Detect a stale read | Optimistic count comparison, failed attempt and fresh retry |
| 5. Compare isolation levels | Repeatable Read and Serializable runs, SQLSTATE and whole-transaction retry |
| 6. Handle repeated requests | Same ID concurrently, changed details, A commits and A rolls back |
| 7. Ask AI to review your implementation | Prompt, response, predicted result, actual test and decision |
| 8. Compare the results | Every approach, its limitations and your choice for quiet and busy trips |

Do not select just one approach. Keep the unsuccessful experiments too.

## Your files

| File | Use |
| --- | --- |
| `sql/book.sql` | Implement the booking function. It initially raises an error. |
| `docs/evidence.md` | Fill in the run log, comparison and required AI review. |
| `docs/experiments.md` | Follow session examples and adapt the SQL fragments. |
| `sql/variants/` | Save your separate implementations here; see its README. |

Keep the supplied schema, constraints and unsafe scripts unchanged. The
`reserved_seats` column represents the same reservations as the booking rows:
the two counts must agree for each trip. This fixture has no payments or booking
cancellations.

### Function contract

```sql
SELECT lab09.book('request-A', 'passenger-A', 'T-LAST');
```

Arguments are request ID, passenger ID and trip ID. Return the stored booking ID.
One successful request reserves one seat and inserts one booking in the caller's
transaction. A new request for a full, cancelled or missing trip must raise an
error without leaving a reservation or booking behind.

The request ID identifies one logical booking globally in this lab. Repeating a
successful request with the same passenger and trip returns its original ID,
including when that trip is now full or cancelled. Reusing its ID with a different
passenger or trip must raise an error and preserve the original booking.
Concurrent copies of the same request must leave one booking and one reservation.

Only successful bookings are stored. A rejected attempt does not claim its
request ID permanently. Use Read Committed for tasks 2 to 4 and 6. Set the isolation level explicitly
in each session for task 5.
The function cannot commit; the caller chooses `COMMIT` or `ROLLBACK`.

## Open two sessions

Open two terminal windows, A and B. In **each**, run:

```sh
docker compose exec postgres psql -X -U mobility -d mobility_l09 -v ON_ERROR_STOP=1 -v VERBOSITY=verbose
```

At each `psql` prompt:

```sql
\pset pager off
```

The following commands go into those `psql` sessions. A waiting command will not
show a new prompt until the other transaction finishes. After an error inside
`BEGIN`, run `ROLLBACK` before trying another experiment. Exit with `\q`.

## Unsafe sequence

Start from reset data. In **A**, read the available seat and pause:

```sql
\set trip_id T-LAST
\set request_id unsafe-A
\set passenger_id passenger-A
BEGIN ISOLATION LEVEL READ COMMITTED;
\i /lab/sql/unsafe-read.sql
```

In **B**, read the same seat and pause:

```sql
\set trip_id T-LAST
\set request_id unsafe-B
\set passenger_id passenger-B
BEGIN ISOLATION LEVEL READ COMMITTED;
\i /lab/sql/unsafe-read.sql
```

Both sessions should report `reserved_seats=0` and `can_book=t`. Now, in **A**:

```sql
\i /lab/sql/unsafe-write.sql
COMMIT;
```

Then, in **B**:

```sql
\i /lab/sql/unsafe-write.sql
COMMIT;
```

Inspect from either session:

```sql
\i /lab/sql/inspect.sql
```

For `T-LAST`, expect capacity **1**, reserved seats **1**, booking count **2**
and `counts_agree=f`. The unsafe writer uses the value each session read earlier.
Both operations used a transaction and kept the table constraints enabled.

## Load and check your implementation

After editing `sql/book.sql`, use a shell terminal:

```sh
docker compose exec -T postgres bash /lab/run.sh load
docker compose exec -T postgres bash /lab/run.sh check
```

The check deliberately fails while the function is a stub. It checks successful
bookings, full/cancelled/missing trips, repeated and conflicting requests, two
available seats, and rollback after a successful call. Its temporary fixture
changes are rolled back, preserving your experiment data. Close unfinished
transactions first; a five-second lock timeout catches sessions still holding locks.

These are single-session checks for the final function. Intermediate variants
may not handle repeated requests yet. Use the schedules below and the experiment
examples to check concurrency. For an optimistic stale-read experiment, use
separate SQL statements so you can pause between reading and writing.

## Competing bookings

Reset first. In **A**:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT lab09.book('request-A', 'passenger-A', 'T-LAST');
```

Leave A's transaction open. In **B**:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT lab09.book('request-B', 'passenger-B', 'T-LAST');
```

B should wait. In **A**, run `COMMIT;`. B should then reject its request; run
`ROLLBACK;` in B. Inspect the rows. `T-LAST` must have one reservation and one
booking, belonging to A.

### A rolls back

Reset and repeat those calls. This time run `ROLLBACK;` in A. B should then
return a booking ID. Run `COMMIT;` in B. One booking and one reservation should
remain, belonging to B.

## Repeated requests

Reset. In **A**, then **B**, run this identical pair of statements:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT lab09.book('repeat-A', 'passenger-A', 'T-TWO');
```

Leave A open while you start B. Commit A, then commit B once its call returns.
Both calls must return the same booking ID. `T-TWO` must have **one** reservation
and **one** booking, even though another seat was available.

From either session, repeat the same `SELECT` once more. Then try the same request
ID with `passenger-B` or `T-OTHER`. Those changed requests must be rejected without
altering the original booking.

## Repeatable Read and Serializable comparison

Reset and repeat the **unsafe** schedule, changing both `BEGIN` commands to:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
```

Both sessions must finish their reads before A writes. Let A write and commit,
then let B try its write. B should receive SQLSTATE **`40001`**. Roll back B and
inspect: only A's booking should exist.

In B, start a new transaction and rerun `unsafe-read.sql`. The new read should
find the trip full. Stop the attempt without booking and roll back. Retrying the
whole operation includes making that availability decision again.

Repeat from reset data with `BEGIN ISOLATION LEVEL SERIALIZABLE;` in both
sessions. Keep both reads before A's write. Save the actual error and show a
fresh transaction making the availability decision again. See task 5 for the
comparison and retry questions.

This schedule demonstrates a conflict on one trip row. It does not establish that
Repeatable Read prevents every concurrency anomaly.

## Save output and stop

Copy relevant session commands and results into your notes. You can save the
committed rows from a shell terminal with:

```sh
docker compose exec -T postgres bash /lab/run.sh inspect > docs/last-seat-result.txt
```

Use distinct filenames for the unsafe and corrected results. Finish transactions
and leave both `psql` sessions before stopping:

```sh
docker compose stop
```

For startup problems, use `docker compose logs postgres`.
