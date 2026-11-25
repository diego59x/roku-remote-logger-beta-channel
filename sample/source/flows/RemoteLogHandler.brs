' Flow C adapter: a handler for the host logger that forwards each entry to the library.
' Create it after RemoteLogger_init, because the facade looks for the logger Task once, when built.
function RemoteLogHandler() as object
    return {
        log: RemoteLogger("host"),
        ' Host level names that differ from the library's; the others pass through.
        levels: { warning: "warn", verbose: "debug" },
        emit: RemoteLogHandler_emit
    }
end function

sub RemoteLogHandler_emit(entry as object)
    level = entry.levelName
    if m.levels.doesExist(level) then level = m.levels[level]
    m.log.write(level, entry.name, entry.message, entry.extra)
end sub
