sub init()
    m.rightPressCount = 0
    m.dialogOpened = false
    m.ticks = 0

    m.status = m.top.findNode("status")
    m.ticker = m.top.findNode("ticker")

    m.ticker.observeField("fire", "onTick")
    m.top.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    ' Let the standard keyboard dialog handle text entry and its button navigation.
    if m.dialogOpened then return false
    if not press then return true

    if key = "right"
        m.rightPressCount = m.rightPressCount + 1
    else
        m.rightPressCount = 0
    end if

    if m.rightPressCount = 5 then openConfigDialog()
    return true
end function

sub openConfigDialog()
    m.dialogOpened = true
    m.hostDialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    if m.hostDialog = invalid
        m.dialogOpened = false
        m.status.text = "Could not open the host configuration dialog."
        return
    end if

    m.hostDialog.title = "Set the RemoteLogger host"
    m.hostDialog.message = ["Enter an HTTP endpoint, for example http://192.168.1.25:8085/v1/logs"]
    m.hostDialog.buttons = ["Connect", "Cancel"]
    m.hostDialog.keyboardDomain = "generic"
    m.hostDialog.text = "http://"
    m.hostDialog.observeField("buttonSelected", "onConnect")
    m.hostDialog.observeField("wasClosed", "onConfigDialogClosed")
    m.top.dialog = m.hostDialog
end sub

sub onConnect()
    if m.hostDialog.buttonSelected = 1
        m.hostDialog.close = true
        m.dialogOpened = false
        return
    end if

    endpoint = m.hostDialog.text
    if not isValidRemoteLoggerEndpoint(endpoint)
        m.status.text = "Invalid URL. Enter a value such as http://192.168.1.25:8085/v1/logs"
        return
    end if

    started = RemoteLogger_init({
        enabled: true,
        endpoint: endpoint,
        sessionTags: { app: "sample-sequence" }
    })
    if not started
        m.status.text = "RemoteLogger did not start. Check the packaged logger and try again."
        return
    end if

    m.hostDialog.close = true
    m.dialogOpened = false
    m.status.text = "Remote logging started: " + endpoint
    m.log = RemoteLogger("MainSceneSequence")

    if m.log = invalid
        m.status.text = "RemoteLogger did not start. Check the packaged logger and try again."
        return
    end if

    m.log.info("sample-sequence started", { endpoint: endpoint })
    m.ticker.control = "start"

    m.worker = CreateObject("roSGNode", "WorkerTask")
    m.worker.control = "run"
end sub

sub onConfigDialogClosed()
    m.dialogOpened = false
end sub

function isValidRemoteLoggerEndpoint(endpoint as string) as boolean
    hostLabel = "[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?"
    host = "(" + hostLabel + "[.])*" + hostLabel
    port = "(:([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?"
    path = "(/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?"
    query = "([?][A-Za-z0-9._~!$&'()*+,;=:@%/?-]*)?"
    fragment = "(#[A-Za-z0-9._~!$&'()*+,;=:@%/?-]*)?"
    pattern = "^https?://" + host + port + path + query + fragment + "$"
    matcher = CreateObject("roRegex", pattern, "i")
    return matcher.IsMatch(endpoint)
end function

sub onTick()
    m.ticks = m.ticks + 1
    m.log.info("heartbeat", { count: m.ticks, uptimeSec: m.ticks * 5 })
end sub
