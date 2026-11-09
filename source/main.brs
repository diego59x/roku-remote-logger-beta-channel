sub Main()
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    m.scene = screen.CreateScene("MainScene")
    screen.getGlobalNode().addFields({ mainscene: m.scene })
    screen.show()

    m.scene.signalBeacon("AppLaunchComplete")
    m.scene.observeField("exitApp", m.port)


    while(true)
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent" then
            field = msg.getField()
            if field = "exitApp" then
                return
            end if
        end if
    end while
end sub

