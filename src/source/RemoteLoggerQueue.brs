' Ring buffer with a fixed capacity. Plain functions over an AA so the Task keeps it in a local
' and the logic is testable without a thread.
function RemoteLogger_queueNew(capacity as integer) as object
    return {
        items: CreateObject("roArray", capacity, true),
        capacity: capacity,
        head: 0, ' index of the oldest entry
        count: 0,
        dropped: 0
    }
end function

' When full, the oldest entry is overwritten and counted in q.dropped.
sub RemoteLogger_queuePush(q as object, entry as dynamic)
    if q.count = q.capacity
        q.items[q.head] = entry
        q.head = (q.head + 1) mod q.capacity
        q.dropped = q.dropped + 1
    else
        q.items[(q.head + q.count) mod q.capacity] = entry
        q.count = q.count + 1
    end if
end sub

' Removes and returns up to max of the oldest entries, oldest first.
function RemoteLogger_queueTake(q as object, max as integer) as object
    n = q.count
    if max < n then n = max
    if n < 0 then n = 0
    taken = CreateObject("roArray", n, false)
    for i = 1 to n
        taken.push(q.items[q.head])
        q.items[q.head] = invalid ' release the reference
        q.head = (q.head + 1) mod q.capacity
    end for
    q.count = q.count - n
    return taken
end function

function RemoteLogger_queueCount(q as object) as integer
    return q.count
end function
