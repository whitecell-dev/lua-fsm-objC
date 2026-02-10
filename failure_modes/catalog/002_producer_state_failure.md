002: Producer Fails to Send Messages After First Batch

Evidence Status: REPRODUCED
Date: 02/09/2026
Test: /breakage_suite/mailbox_overflow_isolated.lua
Observable Behavior

A producer FSM successfully sends its first batch of messages to a consumer. In all subsequent attempts to send a new batch, the consumer's mailbox remains empty. The log shows Processing mailbox for CONSUMER (0 messages) for batches 2 through N.
Failure Mode

The producer FSM enters a non-functional state after its first batch, where its send_batch event no longer results in messages being delivered.
Hypothesis for Root Cause

    The producer's internal state is corrupted after the first batch.
    The send() function itself has a bug that prevents it from adding to the mailbox queue after the first call.
    The event triggering mechanism (producer:send_batch()) fails to invoke the onleaveIDLE callback on subsequent attempts.

Workarounds

NONE DOCUMENTED.
