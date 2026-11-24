' A stand-in for a host app's own logger: its own level names and a list of handlers.
' It knows nothing about the remote logger; Flow C adds a handler without changing it.
function HostLogger(name as string) as object
    logger = {
        name: name,
        levels: { error: 1, warning: 2, info: 3, verbose: 4 },
        level: 4,
        handlers: [],
        addHandler: HostLogger_addHandler,
        log: HostLogger_log,
        error: HostLogger_error,
        warning: HostLogger_warning,
        info: HostLogger_info,
        verbose: HostLogger_verbose
    }
    logger.addHandler(ConsoleLogHandler())
    return logger
end function

sub HostLogger_addHandler(handler as object)
    m.handlers.push(handler)
end sub

sub HostLogger_log(levelName as string, message as string, extra as dynamic)
    if m.levels[levelName] > m.level then return
    entry = { levelName: levelName, name: m.name, message: message, extra: extra }
    for each handler in m.handlers
        handler.emit(entry)
    end for
end sub

sub HostLogger_error(message as string, extra = invalid as dynamic)
    m.log("error", message, extra)
end sub

sub HostLogger_warning(message as string, extra = invalid as dynamic)
    m.log("warning", message, extra)
end sub

sub HostLogger_info(message as string, extra = invalid as dynamic)
    m.log("info", message, extra)
end sub

sub HostLogger_verbose(message as string, extra = invalid as dynamic)
    m.log("verbose", message, extra)
end sub

function ConsoleLogHandler() as object
    return { emit: ConsoleLogHandler_emit }
end function

sub ConsoleLogHandler_emit(entry as object)
    print UCase(entry.levelName); " "; entry.name; ": "; entry.message
end sub
