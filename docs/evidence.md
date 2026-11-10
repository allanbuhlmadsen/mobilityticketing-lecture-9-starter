# Concurrency evidence

Two psql sessions, A and B, connected to `mobility_l09` in the lecture container, with `VERBOSITY=verbose` so that every error reports its SQLSTATE. Each session sets its own prompt to `A=#` or `B=#`, because the two are otherwise identical on screen and the whole lab turns on which statement ran where. Shell commands run in a third terminal. The fixture is reset between runs, after both sessions have ended their transactions.

Fixture: `T-LAST` capacity 1, `T-TWO` capacity 2, `T-OTHER` capacity 2, `T-CANCELLED` capacity 1 and status Cancelled. All counters start at 0.

## Experiment log

| # | Experiment | Isolation | Order in A | Order in B | Waiting | Error (SQLSTATE) | Final bookings | Final reserved_seats |
| ---: | --- | --- | --- | --- | --- | --- | ---: | ---: |
| 1 | Unsafe read-then-write on T-LAST, counter set from the session's own reading | Read Committed | BEGIN, read (0, can_book=t), write `reserved_seats = 0 + 1`, INSERT, COMMIT | BEGIN, read (0, can_book=t) **before A wrote**, then after A committed: write `reserved_seats = 0 + 1`, INSERT, COMMIT | None. A had committed before B wrote. | None. Both transactions succeeded. | 2 on T-LAST | 1 |
| 2 | The same race with the counter incremented from the row: `reserved_seats = reserved_seats + 1` | Read Committed | BEGIN, read (0, t), write, INSERT, COMMIT | BEGIN, read (0, t) before A wrote, then after A committed: write fails, ROLLBACK | None. A had committed before B wrote. | `23514` check_violation on `trips_check`. `Failing row contains (T-LAST, Scheduled, 1, 2).` The INSERT never ran. | 1 on T-LAST | 1 |
| 3 | `lab09.book` with a conditional UPDATE. A books T-LAST and holds its transaction open; B books the same trip | Read Committed | BEGIN, `book('request-A', 'passenger-A', 'T-LAST')` returns 1, COMMIT | BEGIN, `book('request-B', 'passenger-B', 'T-LAST')` blocks until A commits, then fails; ROLLBACK | B waited on A's row lock on `T-LAST` for as long as A's transaction stayed open | `P0001` raise_exception: `No seat reserved for trip T-LAST: missing, cancelled or full` | 1 on T-LAST, id 1, request-A | 1 |
| 4 | The same, except that A rolls back while B is waiting | Read Committed | BEGIN, `book('request-A', 'passenger-A', 'T-LAST')` returns 1, ROLLBACK | BEGIN, `book('request-B', 'passenger-B', 'T-LAST')` blocks, then succeeds and returns **2**; COMMIT | B waited on A's row lock until A rolled back | None | 1 on T-LAST, id 2, request-B | 1 |
| 5 | Explicit row lock: `SELECT ... FOR UPDATE` before reading availability. A books T-LAST and holds its transaction open; B books the same trip | Read Committed | BEGIN, `book('request-A', ..., 'T-LAST')` returns 1, COMMIT | BEGIN, `book('request-B', ..., 'T-LAST')` blocks on `FOR UPDATE`, then fails; ROLLBACK | B waited on A's row lock on `T-LAST` until A committed | `P0001`: `No seat reserved for trip T-LAST: the trip is full` | 1 on T-LAST, id 1 | 1 |
| 6 | The same row lock, except that A rolls back while B waits | Read Committed | BEGIN, `book(...)` returns 1, ROLLBACK | BEGIN, `book('request-B', ..., 'T-LAST')` blocks, then succeeds and returns 2; COMMIT | B waited until A rolled back | None | 1 on T-LAST, id 2 | 1 |
| 7 | Row lock and a different trip. A holds T-LAST; B books T-OTHER, then tries T-LAST | Read Committed | BEGIN, `book('request-A', ..., 'T-LAST')` returns 1, held open, COMMIT at the end | BEGIN, `book('request-B', ..., 'T-OTHER')` returns 2 **with no wait**, COMMIT. Then BEGIN, `book('request-C', ..., 'T-LAST')` blocks, fails, ROLLBACK | None on T-OTHER. B waited only for T-LAST, and only for as long as A's transaction was open | `P0001`: `the trip is full`, on the T-LAST attempt only | 2: id 1 on T-LAST, id 2 on T-OTHER | 1 on T-LAST, 1 on T-OTHER |
| 8 | Table lock: `LOCK TABLE lab09.trips IN EXCLUSIVE MODE` before anything is read. A books T-LAST and holds its transaction open; B books the same trip | Read Committed | BEGIN, `book('request-A', ..., 'T-LAST')` returns 1, COMMIT | BEGIN, `book('request-B', ..., 'T-LAST')` blocks at `LOCK TABLE`, then fails; ROLLBACK | Measured in `pg_stat_activity` while B waited: B `active` with `wait_event_type = Lock` and `wait_event = relation`, `pg_blocking_pids` pointing at A. A sat `idle in transaction` waiting on `ClientRead` | `P0001`: `the trip is full` | 1 on T-LAST, id 1 | 1 |
| 9 | The same table lock, except that A rolls back while B waits | Read Committed | BEGIN, `book(...)` returns 1, ROLLBACK | BEGIN, `book('request-B', ..., 'T-LAST')` blocks, then succeeds and returns 2; COMMIT | B waited until A rolled back | None | 1 on T-LAST, id 2 | 1 |
| 10 | Table lock and a different trip. A holds T-LAST; B books T-OTHER | Read Committed | BEGIN, `book('request-A', ..., 'T-LAST')` returns 1, held open, COMMIT | BEGIN, `book('request-B', ..., 'T-OTHER')` **blocks**, and returns 2 only after A commits; COMMIT | Measured: B on `Lock` / `relation`, blocked by A, waiting for a trip A had never touched. Compare experiment 7, where the row lock let the identical booking through immediately | None | 2: id 1 on T-LAST, id 2 on T-OTHER | 1 on T-LAST, 1 on T-OTHER |
| 11 | Advisory lock: `pg_advisory_xact_lock(9009, key)`, with the key from `lab09.trip_lock_key`. A books T-LAST and holds its transaction open; B books the same trip | Read Committed | BEGIN, `book('request-A', ..., 'T-LAST')` returns 1, COMMIT | BEGIN, `book('request-B', ..., 'T-LAST')` blocks on the advisory lock, then fails; ROLLBACK | Measured: B `wait_event = advisory`, blocked by A. `pg_locks` showed both sessions on `classid 9009, objid 1`, A with `granted = t` and B with `granted = f` | `P0001`: `the trip is full` | 1 on T-LAST, id 1 | 1 |
| 12 | The same advisory lock, except that A rolls back while B waits | Read Committed | BEGIN, `book(...)` returns 1, ROLLBACK | BEGIN, `book('request-B', ..., 'T-LAST')` blocks, then succeeds and returns 2; COMMIT | B waited on the advisory lock until A rolled back. `pg_advisory_xact_lock` is released by a rollback as reliably as by a commit | None | 1 on T-LAST, id 2 | 1 |
| 13 | A books through the function, which takes the advisory lock. B runs the supplied unsafe scripts, which never take it | Read Committed | BEGIN, `book('request-A', ..., 'T-LAST')` returns 1, held open, COMMIT | BEGIN, `unsafe-read.sql` reads (0, can_book=t) **without waiting**, `unsafe-write.sql` blocks on its UPDATE, then writes the stale `0 + 1` and inserts; COMMIT | Measured: B on `wait_event = transactionid`, the row lock taken by the UPDATE — not the advisory lock. `pg_locks` for advisory showed **one row only**: A holding 9009/1. B was absent from it entirely | None. Both transactions succeeded | **2 on T-LAST**, ids 1 and 2 | 1, and `counts_agree = f` |
| 14 | Deadlock from opposite lock order. Plain `SELECT ... FOR UPDATE`, no booking involved | Read Committed | BEGIN, lock T-LAST, then request T-OTHER and block; received it after B rolled back; ROLLBACK | BEGIN, lock T-OTHER, then request T-LAST | A blocked from the moment it asked for T-OTHER. B blocked for about a second, until its own deadlock check found the cycle | `40P01` deadlock detected, raised in **B**. `DETAIL`: process 5888 waits for transaction 880, blocked by 5784; process 5784 waits for transaction 881, blocked by 5888. `CONTEXT: while locking tuple (0,1) in relation "trips"` | 0 | 0 |
| 15 | The same two rows, but both sessions lock in the same order: T-LAST first, then T-OTHER | Read Committed | BEGIN, lock T-LAST, lock T-OTHER, ROLLBACK | BEGIN, lock T-LAST (blocked until A rolled back), then lock T-OTHER; ROLLBACK | B waited for T-LAST only, and only for as long as A held it. A never waited for anything | None | 0 | 0 |
| 16 | Optimistic check on T-TWO, capacity 2. Both sessions read the same count before either writes. A commits, B attempts, fails and retries in a new transaction | Read Committed | BEGIN, `book('opt-A', ..., 'T-TWO')` returns 1, held open, COMMIT | BEGIN, `book('opt-B', ..., 'T-TWO')` reads 0 and blocks on its UPDATE, then fails; ROLLBACK. New BEGIN, the same call returns 2 with no wait; COMMIT | Measured: B `active` on `Lock` / `transactionid`, blocked by A, although this version takes no explicit lock anywhere. A sat `idle in transaction` on `ClientRead`. The retry waited for nothing | `P0001` on the first attempt only: `Optimistic check failed for trip T-TWO: it is cancelled, it is full, or reserved_seats is no longer 0` | 2 on T-TWO: id 1 `opt-A`, id 2 `opt-B` | 2 on T-TWO, `counts_agree = t` |
| 17 | The same version on T-LAST, capacity 1, where the trip really is full after A. A commits | Read Committed | BEGIN, `book('last-A', ..., 'T-LAST')` returns 1, COMMIT | BEGIN, `book('last-B', ..., 'T-LAST')` reads 0 and blocks, then fails; ROLLBACK | B waited on A's row lock until A committed | `P0001`, word for word the message from experiment 16 with T-LAST in place of T-TWO. **Two** conditions failed here rather than one: `reserved_seats < capacity` as `1 < 1`, and `reserved_seats = 0` as `1 = 0` | 1 on T-LAST, id 1, `last-A` | 1 |
| 18 | The same version on T-LAST, except that A rolls back while B waits | Read Committed | BEGIN, `book('roll-A', ..., 'T-LAST')` returns 1, ROLLBACK | BEGIN, `book('roll-B', ..., 'T-LAST')` reads 0 and blocks, then succeeds and returns **2**; COMMIT | B waited on A's row lock until A rolled back. No retry was needed | None | 1 on T-LAST, id 2, `roll-B` | 1 |
| 19 | The supplied unsafe read-then-write on T-LAST, unchanged, with both sessions at Repeatable Read. Both read before A writes, A commits, B writes. Then B retries the whole transaction | Repeatable Read | BEGIN, `unsafe-read.sql` reads (0, can_book=t), `unsafe-write.sql` writes and inserts id 1, COMMIT | BEGIN, `unsafe-read.sql` reads (0, t) **before A wrote**; after A committed, `unsafe-write.sql` fails; ROLLBACK. New BEGIN, `unsafe-read.sql` now reads (1, can_book=**f**), `unsafe-write.sql` takes its `\else` branch and writes nothing; COMMIT | None. A had committed before B wrote, so B never blocked | `40001` could not serialize access due to concurrent update, raised in `ExecUpdate`, that is by the UPDATE statement itself. The INSERT never ran | 1 on T-LAST, id 1, `rr-A` | 1, `counts_agree = t` |
| 20 | The same sequence with both sessions at Serializable | Serializable | BEGIN, read (0, t), write, insert id 1, COMMIT | BEGIN, read (0, t) before A wrote; after A committed the write fails; ROLLBACK. New BEGIN, read (1, f), no write; COMMIT | None | `40001`, **word for word the same message and the same `LOCATION: ExecUpdate`** as experiment 19 | 1 on T-LAST, id 1, `ser-A` | 1, `counts_agree = t` |
| 21 | Replay and misuse of a request id, one session only. Book on T-LAST, repeat the identical request once the trip is full, then reuse the same request id with a different passenger and on a different trip | Read Committed | BEGIN, `book('rep-A', 'passenger-A', 'T-LAST')` returns 1, COMMIT. BEGIN, the identical call returns **1** again, COMMIT. BEGIN, `book('rep-A', 'passenger-B', 'T-LAST')` fails, ROLLBACK. BEGIN, `book('rep-A', 'passenger-A', 'T-OTHER')` fails, ROLLBACK | Not used | None | `P0001` twice, both from line 15, the lookup's mismatch check: `Request rep-A belongs to passenger passenger-A on trip T-LAST, not to passenger passenger-B on trip T-LAST`, and the same message ending `not to passenger passenger-A on trip T-OTHER` | 1 on T-LAST, id 1, `rep-A` | 1 on T-LAST, 0 on T-OTHER, `counts_agree = t` everywhere |
| 22 | The same request id, passenger and trip sent concurrently from both sessions against T-TWO, capacity 2, so a seat is genuinely free. A commits | Read Committed | BEGIN, `book('repeat-A', 'passenger-A', 'T-TWO')` returns 1, held open, COMMIT | BEGIN, the identical call: the lookup on `request_id` finds nothing, then `FOR UPDATE` blocks; after A commits the call returns **1**, the same id A received; COMMIT | B waited on A's row lock on T-TWO. The lookup itself never waited, because a plain SELECT does not | None reached the caller. Inside the function B's INSERT raised `23505` unique_violation on `request_id`, caught by `EXCEPTION WHEN unique_violation` | 1 on T-TWO, id 1, `repeat-A` | **1** on T-TWO, `counts_agree = t`. B's increment to 2 was undone together with its insert |
| 23 | The same concurrent identical request, except that A rolls back while B waits | Read Committed | BEGIN, `book('repeat-A', 'passenger-A', 'T-TWO')` returns 1, ROLLBACK | BEGIN, the identical call blocks on `FOR UPDATE`, then succeeds and returns **2**, a booking of its own; COMMIT | B waited on A's row lock until A rolled back | None. The unique_violation handler never fired, because A's row was never committed | 1 on T-TWO, id **2**, `repeat-A` | 1 on T-TWO, `counts_agree = t` |
| 24 | The case proposed by the AI review in task 7: the same request id sent concurrently for two **different** trips, so the two sessions lock different rows and meet only at the unique index | Read Committed | BEGIN, `book('repeat-B', 'passenger-A', 'T-TWO')` returns 1, held open, COMMIT | BEGIN, `book('repeat-B', 'passenger-A', 'T-OTHER')`: the lookup finds nothing, `FOR UPDATE` on T-OTHER is granted at once, the counter on T-OTHER is raised to 1, and the INSERT then blocks; after A commits the call fails; ROLLBACK | Measured: B `active` on `Lock` / `transactionid`, blocked by A, with **no** pending lock on `trips` and no `tuple` lock at all. `pg_locks` showed B holding `ExclusiveLock` on two transaction ids, 999 and 1000 — its main transaction and the subtransaction created by the `EXCEPTION` block — plus an ungranted `ShareLock` on A's transaction id 997 | `P0001` from **line 67**, the mismatch check inside the `EXCEPTION` handler, where experiment 21 reported the same text from line 15, the opening lookup. The `23505` that triggered it never reached the caller | 1 on T-TWO, id 1, `repeat-B` | 1 on T-TWO, **0 on T-OTHER**, `counts_agree = t` |

## 1. Reproducing the double booking

**The stale value B writes back is the zero.** B's `\echo` reported `seen_reserved=0` at the same moment its own `SELECT` returned `reserved_seats = 1`. The write computes `:seen_reserved + 1`, that is `0 + 1`, and sends the number 1. B does not add one to A's count; it overwrites A's 1 with its own 1, and A's increment disappears without a trace.

**Two committed bookings can coexist with a counter of one** because the two numbers are maintained by different statements, and only one of them can be overwritten. `INSERT` always adds a row and cannot overwrite anything. `UPDATE` assigns an absolute value and can. Both sessions' bookings survived; only one session's counting did.

**`BEGIN` and `COMMIT` did not prevent it** because a transaction promises that your own changes take effect together or not at all — not that nobody else gets anything done in the meantime. Both transactions kept that promise exactly. The damage happened between B's read and B's write, and that interval is not what a transaction covers. B's own `SELECT` proved the point: it saw the truth and wrote something else, because the decision was held in a psql variable rather than in the database.

**The `CHECK` accepted it** because `CHECK (reserved_seats >= 0 AND reserved_seats <= capacity)` only sees the value being written, and the value written was 1. Capacity is 1. One is not greater than one. The constraint never saw the number 2, because nobody ever computed it.

**What the constraint protects** is one row's own invariant, and nothing else. It cannot see the `bookings` table, so it does not prove that the booking rows agree with the counter: experiment 1 ended with a counter of 1, two bookings and a perfectly satisfied constraint. In experiment 2 the two figures do agree, but that is because the failing transaction rolled back, not because any constraint compared them.

**If the booking insert committed separately**, the two changes would stop being one unit and two new failure modes would appear. A failing counter update with an already committed insert leaves a booking with no reserved seat. A failing insert with an already committed counter leaves a seat reserved for nobody, and the trip looks fuller than it is for good. In experiment 2 the INSERT never ran, but that was `ON_ERROR_STOP` halting the file, not the database protecting anything. The guarantee that both changes happen or neither does comes only from their sharing one transaction.

## 2. The conditional update

The function now increments the counter with a single statement whose `WHERE` clause carries all three conditions:

    UPDATE lab09.trips
       SET reserved_seats = reserved_seats + 1
     WHERE id = p_trip_id
       AND status = 'Scheduled'
       AND reserved_seats < capacity
    RETURNING reserved_seats INTO v_reserved;

**The capacity decision is made by that `WHERE` clause**, and specifically by `reserved_seats < capacity`, at the moment the row is written. Not by an earlier `SELECT`, and not by the application. The decision and the write are the same action, so there is no interval between them in which anything can change.

**Reading availability first is insufficient** because the answer can change between the read and the write, and nothing about a transaction prevents that. Experiment 1 is the proof: B read zero, could afterwards see the one with its own eyes, and still wrote its zero-plus-one.

**A conditional update does not avoid waiting for another writer.** In both experiments B stopped dead until A had finished. What the conditional update removes is not the queue but the staleness: it moves the decision to *after* the wait. Experiments 3 and 4 show this from both sides — the same code and the same wait produced opposite outcomes, decided entirely by what A ended up doing, because B re-reads the row when it wakes. In Read Committed, an `UPDATE` that finds a row locked re-evaluates its `WHERE` clause against the version the other transaction left behind.

**A zero-row result tells you that no seat was reserved**, and therefore that no booking may be written. It cannot distinguish three different situations: the trip does not exist, the trip is cancelled, or the trip is full. All three produce zero rows from the same statement, which is why the error text has to say "missing, cancelled or full" — the statement honestly does not know which. Telling the passenger why would need a separate read afterwards, and that read is purely informational: by the time it runs, the answer may have changed again. It can report what was wrong, not what is wrong.

**One incidental finding from experiment 4.** A's rolled-back attempt had already taken booking id 1 from the identity sequence, so B's successful booking received id 2. Identity sequences are not rolled back, because they have to hand out numbers to many concurrent transactions without waiting to see which ones commit. A gap in the ids is normal and is not evidence that anything went wrong.

This version is kept as `sql/variants/02-conditional.sql`.

## 3. Explicit locks

### Row lock: `SELECT ... FOR UPDATE`

The trip row is locked before its availability is read, which is the order the task calls for. Reading first and locking afterwards would recreate the problem from task 1 exactly. A session that finds the row already locked joins a queue, and when it is let through it receives the row in its **newest** version — the same re-read we saw in task 2, triggered by a lock instead of by an update.

Because the row is held, the `UPDATE` no longer needs `AND reserved_seats < capacity` in its `WHERE` clause. The decision has already been made and nothing can change the row in between. That is what the lock buys.

**It also buys a better error message, and this is the sharpest contrast with task 2.** A zero-row conditional update cannot distinguish "missing", "cancelled" and "full" — all three look identical. Here the row is in hand and can be inspected, so each rejection gets its own text. Experiments 5 and 7 both report `the trip is full` rather than `missing, cancelled or full`. The more useful message is not free: it costs an explicit lock.

**Only operations that want the same row wait.** In experiment 7, A held T-LAST with an open transaction and B still booked T-OTHER with no delay whatsoever. B waited only when it asked for T-LAST, and only for as long as A's transaction stayed open.

**The lock is held until the transaction ends, not until the `UPDATE` finishes.** Everything the transaction does after taking it extends the queue for everyone who wants that trip: the insert, any further query, every network round trip, and in a real system a payment or a passenger still making up their mind. Throughput for one trip becomes one booking per lock-holding interval. The design rule follows directly: take the lock as late as possible, commit as soon as possible, and never do anything slow — least of all anything outside the database — while holding it.

This version is kept as `sql/variants/03-row-lock.sql`.

### Table lock: `LOCK TABLE lab09.trips IN EXCLUSIVE MODE`

Only two lines differ from the row-lock version: the table lock is taken as the very first statement, and `FOR UPDATE` is gone from the `SELECT`. Everything else is word for word identical, so the comparison is between two locking strategies and not between two programs.

`EXCLUSIVE` still permits plain `SELECT` — somebody may read — but it excludes every write and every other `EXCLUSIVE` lock, and it covers the whole of `lab09.trips`. Note where it has to be taken: **before** we have even looked up which trip is wanted. It cannot be otherwise, because a table lock knows nothing about rows.

**For a race on the same trip the outcome is identical to the row lock.** Experiments 8 and 9 end exactly as 5 and 6 did: one booking, one seat, and the same `the trip is full` message when A commits, or the seat handed to B when A rolls back. Both locks protect the seat equally well. The difference is not in the outcome but in who has to queue.

**That difference is experiment 10 against experiment 7, and both sides are measured.** With the row lock, B booked T-OTHER with no delay whatsoever while A held T-LAST. With the table lock, the identical booking blocked on `Lock` / `relation` until A committed — waiting for a trip A had never touched and would never touch.

**What is lost is throughput, not correctness.** The row lock allows one booking at a time *per trip*. The table lock allows one booking at a time *for the entire system*, however many trips there are and however unrelated they may be. With four trips in the fixture that is a factor of four; with a real timetable it is a factor of however many departures the operator runs.

**One operational observation from the measurement.** While B was blocked, A showed as `idle in transaction` with `wait_event = ClientRead`: A was doing no work at all. It was waiting for a human to type the next line, and holding its locks the whole time. The queue does not last as long as the work lasts; it lasts as long as the **transaction** lasts. That is the same point as in the row-lock section, now visible in the server's own view of its sessions.

This version is kept as `sql/variants/04-table-lock.sql`.

### Transaction advisory lock: `pg_advisory_xact_lock(9009, key)`

The two earlier locks were attached to something real: a row and a table. An advisory lock is attached to **a number we invent**. PostgreSQL keeps track of the numbers and lets only one transaction at a time hold a given one, but it has no idea what the number means. We are the ones who decide that `(9009, 1)` stands for "whoever intends to change T-LAST". The mapping lives in `lab09.trip_lock_key` so that every cooperating path computes the same number from the same trip, which is the whole requirement the task states.

The `xact` in the function name means the lock is released when the transaction ends. Experiment 12 confirms that a rollback releases it as reliably as a commit, which is the point of choosing this variant: it cannot be forgotten.

**Can the lock protect code that ignores the convention? No, and experiment 13 is the proof.** A booked through the function and took the lock properly. B ran the supplied unsafe scripts, which know nothing about any advisory lock, and the double booking from task 1 came back unchanged: two bookings on T-LAST with a counter of 1. `pg_locks` filtered to advisory locks showed **a single row** — A holding 9009/1 — with B absent from it entirely, because B never asked.

**The waiting in experiment 13 looked like protection and was not.** B did block, for a noticeable time, and a casual observer would conclude that something was being enforced. The measurement says otherwise: B waited on `transactionid`, the row lock that every `UPDATE` takes automatically. That lock delayed B until A had finished and then let it write its stale value over A's. This is the distinction the task asks for: advisory waiting and row-lock waiting both appear as `wait_event_type = Lock`, but one is voluntary and the other is unavoidable. Only the unavoidable one applies to code that was not written to cooperate.

**A weakness visible in the code itself.** A trip that is absent from `lab09.trip_lock_key` is rejected with `no advisory lock key is defined for it` — not because it does not exist, but because we have no number for it. The hard-coded mapping is the convention made visible, and it is as fragile as any other convention: it protects exactly the trips somebody remembered to add to it.

What an advisory lock can do that a row lock cannot is guard something that has no single row to lock. Here there is a row, so the row lock is the better tool.

This version is kept as `sql/variants/05-advisory.sql`.

### Deadlock and lock ordering

A deadlock needs a cycle, and a cycle needs the two sessions to take their locks in **different** orders, so that each can get halfway and then block on the other's half. Experiment 14 built exactly that: A held T-LAST and asked for T-OTHER; B held T-OTHER and asked for T-LAST.

**The victim was B, and the reason is about timing rather than fault.** PostgreSQL does not detect deadlocks immediately. A session waits for one second on a lock, and only then examines whether a cycle exists; the session whose examination finds the cycle aborts itself. A began waiting first, but at the moment its check ran there was no cycle yet, because B had not asked for anything. B began waiting when the cycle was complete, so B is the one that found it and died.

**The error does not release anything.** When B received `40P01`, its transaction was aborted but still held its locks, and A stayed blocked until B issued `ROLLBACK`. The error reports the problem; the cleanup is still the application's job.

**Experiment 15 removes the possibility entirely** by having both sessions lock T-LAST first and T-OTHER second. B waited for T-LAST while A held it, and then proceeded through both rows without trouble. Whoever reaches the first row first also reaches the second first, so no cycle can form. The order does not have to be clever; it only has to be **the same everywhere**.

**What should the application retry after a deadlock? The whole transaction, from the beginning.** Retrying only the failed statement is not even possible: the transaction is in an aborted state and will reject every statement until it is rolled back. And everything the transaction had done before the failure is gone, so the retry has to read the current state again rather than reuse what it read the first time. By the time the retry runs, another passenger may have taken the seat, and the right answer may have become a refusal. The same argument returns in task 5 for serialization failures.

## 4. The optimistic check

This version takes no lock and tells nobody to wait. It reads the counter in a statement of its own, keeps the value, and then makes that value a condition of the write:

    UPDATE lab09.trips
       SET reserved_seats = reserved_seats + 1
     WHERE id = p_trip_id
       AND status = 'Scheduled'
       AND reserved_seats < capacity
       AND reserved_seats = v_observed
    RETURNING reserved_seats INTO v_reserved;

The decisive difference from task 2 is what the added condition asks. `reserved_seats < capacity` asks "is there a seat?". `reserved_seats = v_observed` asks "is the world unchanged since I looked?". Those are not the same question, and experiments 16 and 17 are the same question answered in opposite directions.

**A failed optimistic check does not mean the trip is full, and experiment 16 proves it.** T-TWO has capacity 2. A took one seat, so one remained. B's update still failed, because the only condition that broke was `reserved_seats = 0` against a counter that now read 1. `status = 'Scheduled'` held and `1 < 2` held. The conditional update from task 2 would have accepted that booking, and would have been right to. B retried in a new transaction, read 1, and was served immediately. The seat had been there the whole time.

**The error message is the same text in both cases, and that is the practical problem.** In experiment 17 on T-LAST the identical message was true: two conditions had broken, and the trip was genuinely full. Experiment 16 and experiment 17 produced messages that differ only in the trip name, while calling for opposite responses from the application — retry in one case, refuse the passenger in the other. The check cannot tell them apart, because a single zero-row update reports only that no row matched. Deciding what to do next needs a fresh read, which is exactly what the retry in experiment 16 performed.

**An optimistic check does not mean the database takes no locks, and this was measured rather than assumed.** While A held its transaction open, `pg_stat_activity` showed B as `active` with `wait_event_type = Lock` and `wait_event = transactionid`, blocked by A's process. The word `FOR UPDATE` does not appear in this version, nor does `LOCK TABLE`, nor `pg_advisory_xact_lock`. The lock B waited on is the one every `UPDATE` takes on the row it changes, and it is not optional. What "optimistic" removes is the *request* for a lock, not the encounter with one. B waited as long under this version as it did under the conditional update and under all three explicit locks.

**Compared with the conditional update, this version costs failures and saves nothing.** When A rolls back the two are indistinguishable: experiment 18 and experiment 4 both show B waiting, waking, succeeding and receiving id 2 after A's rolled-back insert consumed id 1. When A commits they diverge, and the divergence runs the wrong way. The conditional update rejects only once the seat is actually gone; the optimistic check rejects as soon as the number moved, which includes every case where a seat is still free. Both waited the same amount of time, so the extra rejections buy nothing. On this schema, for this rule, the row lock and the conditional update are both better tools.

**One genuine improvement over task 2.** The leading `SELECT ... INTO` can see that a trip does not exist, and `IF NOT FOUND` after it gives the missing trip an error of its own. Task 2's single statement could not distinguish missing, cancelled and full at all. Here only the remaining three stay merged.

**What comparing the count fails to detect.** The schema has no version column, so the check compares the counter, and a counter only reports its own value. If somebody books a seat and the booking is cancelled back again between B's read and B's write, the counter goes 0, then 1, then 0, and B's comparison passes. The check reports "unchanged" when what actually happened is "changed twice". For this lab's single rule that outcome is still correct, because the counter is all the decision depends on. The weakness is that the guarantee is narrower than it appears: the check establishes that one number has the same value, not that nothing has happened to the row. Any decision resting on more than that number is outside what the comparison can see.

**How a version column would change it.** A `version integer` on `lab09.trips`, incremented by every statement that changes the row, and compared as `AND version = v_observed_version`, closes that gap for two reasons. A version only ever moves forward, so it cannot return to an earlier value and hide a pair of changes the way the counter did. And one column then stands for every change to the row, so a decision depending on several columns needs one comparison rather than one per column. The question changes from "has this number moved?" to "has this row been touched?", which is the question an optimistic check is meant to ask. The schema is left unchanged, as the task allows.

This version is kept as `sql/variants/06-optimistic.sql`.

## 5. Isolation levels

This task uses the supplied unsafe scripts exactly as they came, so the only thing that changes between experiment 1 and experiment 19 is the isolation level. The statements and their order are identical.

**The same race, refused.** At Read Committed the sequence produced two bookings with a counter of one and `counts_agree = f`. At Repeatable Read it produced one booking, a counter of one and `counts_agree = t`, because B's write was rejected outright. Nothing about the application changed. The level alone decided whether the lost update was permitted.

**Where the refusal comes from.** The error's `LOCATION` is `ExecUpdate`, so it is the `UPDATE` statement that fails, not the commit. The mechanism is that the first transaction to change a row and commit wins, and any other transaction whose snapshot predates that commit cannot change the same row. At Read Committed the `UPDATE` would simply have re-read the row and carried on with its stale decision, which is exactly what happened in experiment 1. At Repeatable Read the snapshot is fixed for the whole transaction, so carrying on is not an option and the statement is refused instead.

**Why retrying only the failed statement with the old value is insufficient.** `seen_reserved` and `can_book` are psql variables, which live in the client and are not rolled back with the transaction. After B's `ROLLBACK` they still held 0 and `t`. Running `unsafe-write.sql` again without reading first would therefore have written `0 + 1` over A's 1 and recreated the double booking, under a level that had just refused it — the refusal would have bought nothing. The fresh read in B's new transaction returned `reserved_seats=1; can_book=f`, and the write script's `\else` branch declined the booking. The error says the decision was based on a stale picture; it does not say what the new picture is. Only re-reading says that, and re-reading is only meaningful in a new transaction with a new snapshot.

**Why the two levels look alike in this test.** Serializable is built on top of Repeatable Read and keeps the same first-updater-wins rule for direct write conflicts. What Serializable adds is monitoring of what transactions have *read*, so that conflicts between a read and somebody else's write can also be caught. That addition never came into play here, because B wrote directly to the row A had changed, which the shared rule catches on its own. The identical message, SQLSTATE and `LOCATION` in experiments 19 and 20 are therefore the expected result, not evidence that the levels are equivalent.

**An anomaly still possible under Repeatable Read.** The PostgreSQL isolation documentation notes that Repeatable Read does not prevent serialization anomalies: outcomes that no sequential ordering of the transactions could have produced. Such an anomaly needs the two transactions to read overlapping data and then write to *different* rows, so that first-updater-wins has nothing to fire on. This schema offers a ready example, because nothing in it enforces that a passenger holds at most one booking per trip. Two transactions at Repeatable Read could each query `lab09.bookings` for `passenger-A` on `T-TWO`, each find nothing, and each insert a row. The rows are different, so no write conflict exists, both commit, and the passenger ends up booked twice. Run one after the other, the second transaction would have seen the first one's row and declined. Serializable would reject one of them, because there the reads are watched as well as the writes.

**Does protecting this counter prove that all multi-row business rules are safe? No, and the reason is the mechanism rather than the rule.** `reserved_seats` is a single column in a single row, so two competing bookings necessarily collide on that row, and first-updater-wins catches the collision. A rule that spans several rows has no such row to collide on. The protection we measured in experiments 19 and 20 is protection of one row's arithmetic, and it says nothing about anything counted across rows. The `CHECK` constraint had the same limitation in task 1, for the same reason.

**Handling `40001` in the application.** The handling is the same at both levels, because the error is the same and the remedy does not depend on which level raised it: roll back and repeat the transaction from `BEGIN`, redoing **every** read inside it and letting the fresh reads decide again whether to write. Nothing from the failed attempt may be carried over, which is precisely the mistake the psql variables would have invited. What differs between the levels is how often the error is to be expected: Serializable can reject transactions over read-write conflicts that Repeatable Read never notices, so an application running at Serializable needs a retry loop even around transactions that mostly read.

**How many attempts, and what the passenger sees.** Three attempts, then stop. `40001` means somebody else got there first, which clears up by itself when contention is light and does not when it is heavy; retrying without a limit turns a conflict into an unbounded queue and leaves the passenger with no answer at all. After the last failed attempt the passenger should not see the SQLSTATE, and should not see the same message in both cases either. If the final fresh read shows the trip full, the answer is that the seat is gone, and it is final. If it still shows a seat and the writes keep losing, the answer is that the booking could not be completed and can be tried again. The first closes the matter; the second does not.

**An external payment does not belong inside the retry loop.** Repeating the transaction repeats everything inside it, and a payment is not part of the transaction: the database rolls back its own work, not the payment provider's. A payment taken inside the loop would be taken again on every attempt, and every attempt that ended in a rollback would leave a charge with no booking behind it. The payment therefore belongs outside the retried transaction, and it needs the same protection the booking itself gets in task 6 — a stable request identifier, so that a repeat is recognised as the same payment rather than performed as a new one.

No new variant file belongs to this task: it used the supplied unsafe scripts unchanged, as the task requires.

## 6. Repeated requests

The final implementation in `sql/book.sql` solves two problems that need two different mechanisms, and keeping them apart is what makes the function readable.

Capacity is protected by the explicit row lock, chosen over the alternatives in section 3 because it waits only for the trip in question and keeps the row in hand, which is what lets a rejection say why. Repeated requests are handled by a lookup on `request_id` before anything is locked or changed, with the unique constraint on that column as the backstop.

**The lookup has to come first, and not merely for speed.** A replay must be answerable after the trip has filled up or been cancelled, and experiment 21 shows it is: the second identical call returned id 1 while `T-LAST` was full, and the supplied checks go further and replay successfully after the trip is set to `Cancelled`. Both work because the function returns from the booking row without ever reading `lab09.trips`. Were the lookup placed after the lock and the capacity check, those two cases would be rejected by a capacity check that has no business judging a request that was already fulfilled. A replay also costs no lock at all, which matters under load: repeated requests are exactly what arrives when passengers retry.

**The constraint has to be there too, and the two are not redundant.** Experiment 22 is the proof by construction. Both sessions ran the lookup, both found nothing, and both were right at the moment they looked, because A's row did not yet exist in any way B could observe. Without the unique constraint both inserts would have succeeded and one request would have produced two bookings.

**Why a unique request id does not stop two different requests from taking the last seat.** The constraint is on `request_id`, and two passengers competing for a seat send two *different* request ids. Nothing about those two rows conflicts; both inserts are perfectly legal, and the index has no opinion about seats at all. Request-id uniqueness protects against the same request being carried out twice, which is a different problem from two requests wanting the same thing. Experiments 5 and 22 are the two halves of the answer: experiment 5 protects the seat with no request ids involved anywhere, and experiment 22 protects the request id while a seat is still free.

**Why checking for an existing id before inserting is insufficient without the constraint.** Because the check and the insert are two separate statements, and another transaction can commit the same request in between. That is task 1's read-then-write gap again, moved to a different pair of statements. The lookup is an inexpensive answer in the common case; the constraint is the part that is actually load-bearing, because the index evaluates it at write time and there is no interval in which it can be raced.

**Both writes must sit inside the exception block, and the counter in experiment 22 is the measurement that shows why.** When B's insert failed, B had already incremented `reserved_seats` to 2. A caught exception in PL/pgSQL rolls back everything inside its own `BEGIN ... EXCEPTION ... END` block, so the increment was undone with the insert and the final counter read 1 against one booking. Had the `UPDATE` been placed outside the block, it would have survived the catch and `T-TWO` would have shown two reserved seats for a single booking — the counter disagreeing with the bookings, which is the failure this whole lab is about.

**Experiment 23 shows the same code producing the opposite answer, correctly.** When A rolled back, there was no stored booking to replay, so the handler never fired and B's identical request became the one that was actually carried out, with a booking of its own. A returned id is only a promise until the transaction commits.

**One limitation worth recording.** The handler's recovery depends on re-reading `lab09.bookings` and seeing the other transaction's committed row, which only works at Read Committed, where every statement takes a fresh snapshot. At Repeatable Read or Serializable the snapshot predates that commit, the re-read finds nothing, and the bare `RAISE;` sends the original `23505` to the caller instead. That is honest behaviour rather than a silent wrong answer, and Read Committed is the level this task specifies.

**The supplied checks pass.** All nine controls in `sql/check.sql` succeeded, including the replay after cancellation, the three rejections for a reused request id, the full, cancelled and missing trips, the confirmation that no replay or rejection changed any counter, and the rollback of both the booking and the seat after the function had already returned an id.

The final implementation lives in `sql/book.sql`, as the task requires. The six versions built along the way are kept in `sql/variants/`.

## 7. AI review

### The prompt

Sent as a single message. The three bracketed parts were pasted in full: the two `CREATE TABLE` statements from `database/setup.sql`, the whole of `sql/book.sql`, and the complete session transcript of experiment 22 including the inspection output.

    Review this PostgreSQL 17 booking function for concurrency and repeated-request errors.

    Schema: [the two CREATE TABLE statements from database/setup.sql]

    Fixture: T-LAST capacity 1, T-TWO capacity 2, T-OTHER capacity 2, T-CANCELLED capacity 1
    and status Cancelled. All counters start at 0.

    Function: [sql/book.sql in full]

    The function runs inside the caller's transaction and never commits. All my tests run at
    READ COMMITTED. The fixture is reset between runs. I have two psql sessions, A and B, with
    prompts A=# and B=#, and I can run shell commands in a third terminal.

    Here is one two-session experiment, with statement order and actual output. Both sessions
    send the same request id, the same passenger and the same trip, against T-TWO, which has
    capacity 2, so a seat is genuinely free.

    [the full transcript of experiment 22, both sessions and the inspection output]

    Find one case this test does not cover. Give an exact A/B schedule and predict the final
    bookings, counter and any SQLSTATE. State the assumption your suggestion tests.

### The model

ChatGPT, free tier. The interface showed no version number, so none can be recorded.

### The relevant response

The model proposed one uncovered case: the same `request_id` sent concurrently for two **different** trips. Its reasoning, in its own order:

- B's opening lookup finds no existing booking, because A has not committed.
- B locks T-OTHER successfully, because A holds a lock on T-TWO instead.
- B increments T-OTHER's `reserved_seats`.
- B's INSERT blocks, because A has an uncommitted row with the same unique `request_id`.
- After A commits, B's INSERT raises `23505`; the handler rolls back the inner block's counter increment and failed insert, finds A's committed booking, sees that the stored trip differs from the requested one, and raises the custom exception with SQLSTATE `P0001`.
- Predicted final state: T-TWO with one reserved seat and one booking, T-OTHER with none, and one booking row for `repeat-B` on T-TWO.

It stated the assumption under test as: a `request_id` is a globally unique key permanently associated with exactly one passenger and one trip, and reusing it with different parameters must produce an error rather than returning a booking for the wrong trip, creating a second booking, consuming a seat, or leaving an inconsistent counter. Its closing argument for the value of the test was that the original experiment has both sessions contending on the same trip row, while the proposed one has them locking different rows and discovering the conflict only at the unique index during INSERT.

### What the suggestion actually found, which is not what it claimed

**The stated assumption had already been tested.** Experiment 21 reused `rep-A` on a different trip and received exactly the `P0001` the model predicts. The rule was never in doubt.

**What was genuinely untested is the path, not the rule.** In experiment 21 the mismatch was caught by the opening lookup. In the proposed case there is nothing to look up, because A has not committed, so the mismatch can only be discovered by the comparison inside the `EXCEPTION` handler — code that had never been executed by any experiment in this log. The model's closing paragraph gestures at this ("exercises a different concurrency path"), but its stated assumption does not, and the two are not the same claim. The suggestion is worth running for the reason it almost gave.

The model also wrote "idempotency key" throughout, which is not this lab's vocabulary; the column is `request_id`.

### My prediction, written before running it

Agreement with every outcome the model predicted, plus three things it did not address.

First, **where B waits**. Nothing holds T-OTHER, so the row lock is granted at once and B reaches its INSERT, where the unique index finds A's uncommitted row and waits on A's transaction. B therefore blocks at a different statement than in experiment 22, where it blocked at `FOR UPDATE` and the `23505` arrived instantly because A had already committed.

Second, **what the measurement should show**: an ungranted `transactionid` lock held by B against A's transaction id, and — decisively — **no** pending lock on `trips` at all. The absence is the proof, because nothing about `lab09.trips` could then explain B's wait.

Third, **the booking id is 1, not 2**, although B's failed insert consumed 2 from the identity sequence. The gap leaves no row and is invisible in the table.

### The actual result

Every predicted outcome held. The error was `P0001` with the text `Request repeat-B belongs to passenger passenger-A on trip T-TWO, not to passenger passenger-A on trip T-OTHER`, T-TWO ended with one seat and one booking, T-OTHER with none, and the single booking row carried id 1.

**Two observations go beyond what was predicted.**

The error's `CONTEXT` reported `line 67 at RAISE`. Experiment 21 reported the identical message from `line 15`. Line 15 is the opening lookup's mismatch check and line 67 is the handler's, so the line number alone establishes which path ran — the stronger evidence for this experiment's whole purpose, and something neither the model nor I thought to predict.

`pg_locks` showed B holding `ExclusiveLock` on **two** transaction ids, 999 and 1000, where my prediction said one per session. The second is the subtransaction that `BEGIN ... EXCEPTION ... END` creates. Since the rollback of B's counter increment depends entirely on that subtransaction, the mechanism section 6 argues for turns out to be directly observable, and the under-prediction is recorded here rather than tidied away.

### Verdict: accepted, on narrower grounds than offered

Accepted, because the proposed schedule reached code that no other experiment had reached, and the observed rows, the measured locks and the error's line number together show it behaving correctly. Rejected as stated, because the assumption the model named was already covered by experiment 21.

No change was made to the implementation, so no earlier test and no supplied check needed rerunning.

### Conclusion

**What the model identified:** a concurrency schedule in which two sessions carrying the same `request_id` never contend on a trip row and meet only at the unique index, which turned out to be the one path into the function's exception handler that nothing in this log had taken.

**What the experiment established:** that path works. The blocking happens at the INSERT and not at any lock on `trips`, which the measurement shows by the absence of a pending lock there; the caught `23505` never reaches the caller; the counter increment on the second trip is undone with the failed insert, leaving `T-OTHER` at zero; and the mismatch is reported from line 67, proving the handler's own comparison ran rather than the opening lookup's.

**What remains untested.** The handler's `IF NOT FOUND THEN RAISE;` branch has still never executed; reaching it needs a caller at Repeatable Read or Serializable, where the re-read cannot see the other transaction's commit, and section 6's account of that case is reasoned rather than measured. Everything in this log uses exactly two sessions, so nothing is known about three or more. The claim that the final function cannot deadlock on `lab09.trips`, because it locks exactly one row, is an argument from the code and not a measurement. All timing in all 24 experiments was produced by hand, one statement at a time, so nothing here describes behaviour under real contention. And the reasoning in section 5 about external payments inside a retry loop is untested in the strict sense, because this lab contains no payment to repeat.

**The model agreed that the function handles its proposed case correctly, and that agreement is not part of the evidence.** What counts is the line number, the lock table and `T-OTHER`'s zero.