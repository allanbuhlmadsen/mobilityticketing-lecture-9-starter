# The last seat: evidence

## Run log

Add rows for every run. Link to SQL files and labelled A/B transcripts.
For each capacity-protection version, run both A commits and A rolls back.
Include different-trip lock tests, advisory-lock bypass, deadlock and ordered
locking, optimistic retry, and both isolation-level experiments.

| Run / SQL file | Isolation | A/B statement order or transcript | Waiting | A result / SQLSTATE | B result / SQLSTATE | Reserved seats | Booking count | Counts agree? |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | |

## Comparison

Fill every row using your observations. Explain what each method protects and
what it does not. Separate capacity conflicts from repeated requests.

| Version | Observed result and waiting | Failure or limitation | Application response |
| --- | --- | --- | --- |
| Original Read Committed sequence | | | |
| Increment with CHECK constraint | | | |
| Conditional update | | | |
| Explicit row lock | | | |
| Table lock | | | |
| Advisory lock | | | |
| Optimistic count check | | | |
| Repeatable Read | | | |
| Serializable | | | |
| Unique request ID and retry handling | | | |

## Repeated-request checks

- Same successful request after the trip becomes full:
- Same request concurrently on T-TWO, A commits:
- Same request concurrently on T-TWO, A rolls back:
- Existing ID with a different passenger:
- Existing ID with a different trip:
- Full, cancelled and missing trip checks:
- Rollback after the function returns an ID:
- Supplied check output:

## Required AI review

1. Model name and date:
2. Prompt, including schema, your function and one actual test:
3. Relevant response and proposed A/B sequence:
4. Your prediction before running it:
5. Actual commands, output and SQLSTATE:
6. Accept or reject the suggestion, and why:
7. Changes made and checks rerun, if any:
8. What remains untested:

If the suggested test cannot run, keep the original suggestion and explain your
correction. If no useful case is suggested, ask it to challenge an assumption
in your comparison and test that claim.

## Your decision

- Which operation decides whether a seat is available?
- Which changes must commit or roll back together?
- Which approach would you keep for a quiet trip, and why?
- Would you choose differently for a popular departure? Refer to waiting and retries.
- What does the application retry after 40001 or a deadlock? How does it stop retrying?
- Why is a returned ID not yet proof of a committed booking?
- What would go wrong if an external payment were repeated with the transaction?
- Where would you choose a different approach?

Save all SQL variants, including rejected approaches, and the relevant session output.
