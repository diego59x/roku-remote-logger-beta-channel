' Flow B: the host app's one logging helper around print. The remote lines are the only
' addition, so every call site that uses the helper is covered without change.
sub App_log(message as string, data = invalid as dynamic)
    ' Built on the first call: a component whose first call comes before RemoteLogger_init stays silent.
    if m.remoteLog = invalid then m.remoteLog = RemoteLogger("app")
    m.remoteLog.info(message, data) ' added: runs in every build

    if CreateObject("roAppInfo").isDev() ' existing gate stays on print only
        print message; data
    end if
end sub
