sub init()
    m.top.functionName = "RemoteLogger_taskRun"
end sub

' Queues entries and sends them in batches, one request at a time.
' Config is read once; all working state stays in locals.
sub RemoteLogger_taskRun()
    config = m.top.config
    queue = RemoteLogger_queueNew(config.maxQueue)
    port = CreateObject("roMessagePort")
    m.top.observeField("entry", port)
    m.top.observeField("cancel", port)
    session = RemoteLogger_sessionEnvelope(config)
    clock = CreateObject("roTimespan")

    nextSeq = 1
    flushAt = config.flushIntervalMs
    urgent = false ' an error entry is waiting
    batch = invalid ' the batch in flight or waiting to retry
    batchLost = 0 ' entries in dropped batches
    reported = 0 ' lost entries the server has been told about
    sent = 0
    queued = 0
    dropped = 0
    ' A cancel written before observeField sends no event, so read it once here.
    running = not m.top.cancel
    while running
        due = flushAt
        if batch <> invalid then due = batch.due
        timeout = due - clock.totalMilliseconds()
        if timeout < 1 then timeout = 1 ' wait(0) would block forever
        msg = wait(timeout, port)
        now = clock.totalMilliseconds()

        code = invalid
        if type(msg) = "roSGNodeEvent"
            if msg.getField() = "entry"
                entry = msg.getData()
                ' Numbered on arrival, so entries lost to queue overflow leave a gap in seq.
                nextSeq = RemoteLogger_resequence([entry], nextSeq)
                RemoteLogger_queuePush(queue, entry)
                if entry.lvl = "error" then urgent = true
            else if msg.getData() = true
                running = false
            end if
        else if batch <> invalid and RemoteLogger_isReply(msg, batch.xfer)
            code = msg.getResponseCode()
        end if

        if batch <> invalid and now >= batch.due
            if batch.xfer = invalid
                RemoteLogger_batchSend(batch, config, port, now)
            else if code = invalid
                batch.xfer.asyncCancel()
                code = -28 ' curl's timeout code
            end if
        end if
        if code <> invalid
            result = RemoteLogger_batchResult(batch, code, now)
            if result = "ok"
                sent = sent + batch.entries.count()
                reported = reported + batch.dropped
                m.top.sent = sent
                batch = invalid
            else if result = "drop"
                batchLost = batchLost + batch.entries.count()
                batch = invalid
            end if
        end if

        lost = queue.dropped + batchLost
        count = RemoteLogger_queueCount(queue)
        if running and batch = invalid and (count >= config.batchSize or urgent or now >= flushAt)
            flushAt = now + config.flushIntervalMs
            if count > 0
                entries = RemoteLogger_queueTake(queue, config.batchSize)
                batch = { entries: entries, dropped: lost - reported, retries: 0 }
                batch.body = RemoteLogger_buildBody(session, entries, batch.dropped)
                RemoteLogger_batchSend(batch, config, port, now)
                count = RemoteLogger_queueCount(queue)
            end if
            urgent = urgent and count > 0
        end if

        if count <> queued
            queued = count
            m.top.queued = queued
        end if
        if lost <> dropped
            dropped = lost
            m.top.dropped = dropped
        end if
    end while

    ' Last try: the batch in progress plus everything queued, in one request, no retries.
    entries = []
    if batch <> invalid
        if batch.xfer <> invalid then batch.xfer.asyncCancel()
        entries = batch.entries
    end if
    entries.append(RemoteLogger_queueTake(queue, RemoteLogger_queueCount(queue)))
    sent = sent + RemoteLogger_finalFlush(config, port, session, entries, queue.dropped + batchLost - reported)
    m.top.sent = sent
end sub
