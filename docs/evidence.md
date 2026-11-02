# The last seat

## What happened?

| Run | A's result | B's result | Reserved seats | Bookings |
| --- | --- | --- | --- | --- |
| Unsafe, Read Committed | | | | |
| Corrected, A commits | | | | |
| Corrected, A rolls back | | | | |
| Same request in both sessions, T-TWO | | | | |
| Unsafe, Repeatable Read | | | | |

Keep the relevant commands and output with these notes. Identify where B waited
and record any SQLSTATE reported by PostgreSQL.

## Your decision

- Which operation decides whether a seat is available?
- Which changes must commit or roll back together?
- How do you return an existing booking without taking another seat?
- What does the application retry after a serialization failure?
- Which alternative did you consider, and why did you choose your approach?

## AI second opinion

Keep your prompt, the suggested change, and the experiment you used to accept or
reject it. A short note and the relevant output are enough.
