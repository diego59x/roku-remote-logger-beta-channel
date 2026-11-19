sub init()
    m.top.functionName = "doWork"
end sub

' Logs from the Task thread to show entries crossing to the logger Task.
sub doWork()
    logger = RemoteLogger("WorkerTask")
    for i = 1 to 3
        logger.info("work step", { step: i })
        if i < 3 then sleep(1000)
    end for
end sub
