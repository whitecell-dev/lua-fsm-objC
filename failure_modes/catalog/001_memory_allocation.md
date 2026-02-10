001: One-Time Memory Allocation Cost (Incorrectly Labeled as Leak)

Evidence Status: REPRODUCED, ANALYSIS UPDATED
Date: 02/09/2026
Tests: /breakage_suite/mailbox_overflow.lua, /breakage_suite/mailbox_overflow_isolated.lua
Observable Behavior

The system exhibits a significant increase in memory usage (~200 KB) during the first batch of message processing. This memory is not reclaimed by the garbage collector. However, subsequent batches of messages do not cause further memory growth. The system stabilizes at a new, higher baseline.
Failure Mode

This is not a cumulative leak but a one-time allocation of memory that is retained for the lifetime of the FSM instances.
Hypothesis for Root Cause

The FSM's internal structures (e.g., its event table, callback registry, or history) may allocate tables or other objects on first use that are never de-allocated. This is common behavior, but it should be documented as a cost, not a leak.


