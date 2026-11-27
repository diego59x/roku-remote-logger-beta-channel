sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)

    scene = screen.CreateScene("MainSceneSequence")
    screen.getGlobalNode().addFields({ mainscene: scene })
    screen.show()
    scene.signalBeacon("AppLaunchComplete")

    scene.observeField("exitApp", port)
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.getField() = "exitApp"
            return
        end if
    end while
end sub
