# Experiment examples

The [Moodle lab](https://moodle.easv.dk/mod/page/view.php?id=397569) lists the
required tasks. These examples show how to run them. SQL fragments below are
parts of experiments, not a complete booking function.

## Which terminal?

Run `docker compose ...` commands in your normal shell, from the repository root.
Run SQL and commands beginning with `\` at a `psql` prompt. Open the two psql
sessions using the command in the main README. Label their terminal windows A and B.

Before a new experiment, end both transactions with `ROLLBACK;`, then use a shell:

```sh
docker compose exec -T postgres bash /lab/run.sh reset
```

Do not reset while A or B is waiting. Finish the transaction holding the lock first.
Do not paste both sides of a schedule into one session.

## Save and load a function variant

After implementing a conditional-update version in `sql/book.sql`, run in your shell:

```sh
cp sql/book.sql sql/variants/02-conditional.sql
# Later, restore that version:
cp sql/variants/02-conditional.sql sql/book.sql
docker compose exec -T postgres bash /lab/run.sh load
```

Use the other filenames in `sql/variants/README.md` for later versions.
Reset reloads `sql/book.sql`, so restore the intended version before resetting.

## See a row lock in two sessions

This example only reads and locks. It does not reserve a seat.

**1. A:**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT id, capacity, reserved_seats
FROM lab09.trips WHERE id = 'T-LAST' FOR UPDATE;
-- Leave A open. Switch to B.
```

**2. B:**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT id, capacity, reserved_seats
FROM lab09.trips WHERE id = 'T-LAST' FOR UPDATE;
-- This waits. Switch back to A; do not type more commands in B yet.
```

**3. A:**

```sql
ROLLBACK;
```

**4. B:** after the SELECT returns, run:

```sql
ROLLBACK;
```

Repeat with B selecting `T-OTHER`. Record whether it waits. For your booking
version, add the status/capacity decision and both writes before the transaction
ends. Repeat with A committing and rolling back an actual booking.

## Conditional update fragment

Try this inside a transaction, inspect the returned row, then roll back:

```sql
BEGIN;
UPDATE lab09.trips
SET reserved_seats = reserved_seats + 1
WHERE id = 'T-LAST'
  AND status = 'Scheduled'
  AND reserved_seats < capacity
RETURNING id, reserved_seats;
ROLLBACK;
```

The fragment omits the booking insert and request-ID handling. Add those in your
function. Decide what to do when no row is returned. Inside PL/pgSQL you can use
`RETURNING ... INTO` and inspect `FOUND` immediately after the statement.
Do not leave a counter-only update committed.

## Optimistic read and write

Use separate statements so you can make both sessions read before either writes.
In both A and B, begin a Read Committed transaction and run:

```sql
SELECT reserved_seats AS observed
FROM lab09.trips WHERE id = 'T-TWO' \gset
\echo Read reserved_seats = :observed
```

Then adapt this write in each session, letting A finish first:

```sql
UPDATE lab09.trips
SET reserved_seats = reserved_seats + 1
WHERE id = 'T-TWO'
  AND reserved_seats = :observed
  AND status = 'Scheduled'
  AND reserved_seats < capacity
RETURNING reserved_seats;
```

`\gset` stores a psql variable; `:observed` substitutes it in later SQL. This is
not PL/pgSQL syntax. Add a booking only when the update succeeds, with a different
request ID for each passenger. Keep both changes in that same transaction.
After a failed comparison, roll back, begin again and read a new value. Keep the
first result as well as the retry result.

## Table and advisory lock fragments

Acquire the chosen lock inside `BEGIN`, before reading availability:

```sql
-- Table-lock version:
LOCK TABLE lab09.trips IN EXCLUSIVE MODE;

-- Advisory-lock version: use this same mapping in every cooperating path.
-- T-LAST = 1, T-TWO = 2, T-CANCELLED = 3, T-OTHER = 4.
SELECT pg_advisory_xact_lock(9009, 1);
```

Use one approach at a time. The first advisory-lock argument is a namespace for
this lab; the second is the trip key. Use the two-integer form consistently.
Complete your booking transaction, then commit or roll back. For the bypass
experiment, run the unsafe sequence in the other session without taking the
advisory lock and record what happens.

## Make a deadlock deliberately

Start from idle sessions. Run these steps in order:

| Step | A | B |
| --- | --- | --- |
| 1 | `BEGIN;` | |
| 2 | | `BEGIN;` |
| 3 | `SELECT id FROM lab09.trips WHERE id='T-LAST' FOR UPDATE;` | |
| 4 | | `SELECT id FROM lab09.trips WHERE id='T-OTHER' FOR UPDATE;` |
| 5 | `SELECT id FROM lab09.trips WHERE id='T-OTHER' FOR UPDATE;` (waits) | |
| 6 | | `SELECT id FROM lab09.trips WHERE id='T-LAST' FOR UPDATE;` |

PostgreSQL aborts one transaction. Record which one and the SQLSTATE. Run
`ROLLBACK;` in both sessions. Repeat with both taking `T-LAST` before `T-OTHER`;
finish A's transaction so the waiting B can proceed.

## Record what you observed

Example entry for the read-only row-lock demonstration, not a booking test:

| Run | Schedule | Observed result | What this establishes |
| --- | --- | --- | --- |
| Row-lock demonstration | A locks T-LAST; B requests the same lock; A rolls back | B waits, then its SELECT returns; no rows changed | The same row lock conflicts until A ends its transaction. This does not yet test booking correctness. |

Use your own observations for the booking runs. Include both counter and booking
count; one alone can miss a broken invariant. Copy commands and output from each
terminal, labelled A and B. `\o` saves query output but not the complete typed
command history, so do not use that alone as your session transcript.

From a shell you can also save the final rows, using a different filename per run:

```sh
docker compose exec -T postgres bash /lab/run.sh inspect > docs/02-conditional-A-commits.txt
```

## AI review prompt example

Replace the bracketed parts with your own work:

> Review this PostgreSQL 17 booking function for concurrency and repeated-request
> errors. Schema: [schema]. Function: [your function]. Here is one two-session
> experiment, including statement order and actual output: [trace]. Find one
> case this test does not cover. Give an exact A/B schedule and predict the final
> bookings, counter and any SQLSTATE. State the assumption your suggestion tests.

Write your prediction before running the suggested test. Keep the prompt,
response, actual output and your reason for accepting or rejecting the suggestion.
