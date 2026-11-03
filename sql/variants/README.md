# Keep your implementations here

Save separate files as you work:

- `01-increment-check.sql`
- `02-conditional.sql`
- `03-row-lock.sql`
- `03-table-lock.sql`
- `03-advisory-lock.sql`
- `04-optimistic.sql`

These are suggested filenames, not supplied solutions. Each file can contain a
version of `CREATE OR REPLACE FUNCTION lab09.book(...)` or a clearly labelled
manual experiment. Keep the function signature from `sql/book.sql`.
For tasks 1, 4 and 5, keep separate read and write commands so you can pause
between them. Record the isolation level and session order with each experiment.

For a function variant, copy it to `sql/book.sql`, then run `run.sh load` from
the container as shown in the main README. `run.sh reset` also loads
`sql/book.sql`; loading a different file manually and then resetting would
replace that function. Keep your final implementation in `sql/book.sql`.

Do not run a manual experiment script through `run.sh load`. Open psql and run
its statements in the session order you recorded. Keep the original unsafe
scripts unchanged so the baseline remains reproducible.
