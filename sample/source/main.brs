sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    m.scene = screen.CreateScene("MainScene")
    screen.getGlobalNode().addFields({ mainscene: m.scene })
    screen.show()

    ' Dev tool only: a public build must ignore these parameters.
    m.scene.launchArgs = { remoteLog: args.remoteLog, remoteLogLevel: args.remoteLogLevel }

    m.scene.signalBeacon("AppLaunchComplete")
    m.scene.observeField("exitApp", m.port)


    while true
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent"
            field = msg.getField()
            if field = "exitApp"
                return
            end if
        end if
    end while
end sub
