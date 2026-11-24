sub init()
    m.ticks = 0
end sub

' Launch args arrive after init(), so the logger starts here.
sub onLaunchArgs()
    args = m.top.launchArgs
    started = RemoteLogger_init({
        enabled: args.remoteLog <> invalid,
        endpoint: args.remoteLog,
        level: args.remoteLogLevel,
        sessionTags: { app: "sample" }
    })
    status = m.top.findNode("status")
    if started
        status.text = "Remote logging: on, sending to " + args.remoteLog
    else
        status.text = "Remote logging: off (launch with remoteLog=<endpoint>)"
    end if

    m.log = RemoteLogger("MainScene")
    m.log.info("sample started", { "remoteLogging": started })

    ' Flow C: the host logger gets one more handler; its call sites stay as they are.
    m.hostLog = HostLogger("MainScene")
    m.hostLog.addHandler(RemoteLogHandler())

    ticker = m.top.findNode("ticker")
    ticker.observeField("fire", "onTick")
    ticker.control = "start"

    m.worker = CreateObject("roSGNode", "WorkerTask")
    m.worker.control = "run"
end sub

sub onTick()
    m.ticks = m.ticks + 1
    m.log.debug("tick", { count: m.ticks })
    m.log.info("heartbeat", { count: m.ticks, "uptimeSec": m.ticks * 5 })
    m.hostLog.warning("host logger heartbeat", { count: m.ticks })
    if m.ticks = 3 then m.log.error("simulated failure on third tick", { count: m.ticks })
end sub
