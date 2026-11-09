sub TypeGuard_isAssocArray(value as dynamic) as boolean
    return type(value) = "roAssociativeArray"
end sub

sub TypeGuard_isStringNotEmpty(value as dynamic) as boolean
    return type(value) = "string" and len(value) > 0
end sub

sub TypeGuard_isString(value as dynamic) as boolean
    return type(value) = "string"
end sub
