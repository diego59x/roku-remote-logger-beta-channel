sub init()
    m.top.functionName = "sendLog"
end sub

function sendLog() as boolean
    request = m.top.request
    if not TypeGuard_isAssocArray(request) or not TypeGuard_isStringNotEmpty(request.url)
        m.top.response = { success: false, error: "no_url" }
        return true
    end if

    if not TypeGuard_isString(request.message)
        m.top.response = { success: false, error: "invalid_message" }
        return true
    end if

    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    transfer.setPort(port)
    transfer.setUrl(request.url)
    transfer.setCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.initClientCertificates()
    transfer.addHeader("Content-Type", "text/plain; charset=utf-8")

    if not transfer.asyncPostFromString(request.message)
        m.top.response = { success: false, error: "request_not_started" }
        return true
    end if

    event = wait(10000, port)
    if type(event) <> "roUrlEvent"
        transfer.asyncCancel()
        m.top.response = { success: false, error: "timeout" }
        return true
    end if

    return true
end function
