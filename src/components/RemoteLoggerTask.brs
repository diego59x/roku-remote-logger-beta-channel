sub init()
    m.top.functionName = "RemoteLogger_taskRun"
end sub

' Receives entries into a bounded queue. Config is read once; all working state stays in locals.
sub RemoteLogger_taskRun()
    config = m.top.config
    queue = RemoteLogger_queueNew(config.maxQueue)
    port = CreateObject("roMessagePort")
    m.top.observeField("entry", port)
    m.top.observeField("cancel", port)

    queued = 0
    dropped = 0
    ' A cancel written before observeField sends no event, so read it once here.
    running = not m.top.cancel
    while running
        msg = wait(config.flushIntervalMs, port)
        if type(msg) = "roSGNodeEvent"
            if msg.getField() = "entry"
                RemoteLogger_queuePush(queue, msg.getData())
            else if msg.getData() = true
                running = false
            end if
        end if

        count = RemoteLogger_queueCount(queue)
        if count <> queued
            queued = count
            m.top.queued = queued
        end if
        if queue.dropped <> dropped
            dropped = queue.dropped
            m.top.dropped = dropped
        end if
    end while
end sub
