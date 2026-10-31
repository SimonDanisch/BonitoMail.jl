# What the app shows, built from notmuch's JSON (`notmuch search` and
# `notmuch show`, format version 5).

"""
One row of a thread list: who wrote, about what, when, and its tags.
"""
struct ThreadSummary
    id::String
    timestamp::Int
    date::String          # notmuch's relative date, e.g. "Yest. 17:56"
    authors::String
    subject::String
    matched::Int          # messages matching the query
    total::Int            # messages in the thread
    tags::Vector{String}
end

ThreadSummary(t::AbstractDict) = ThreadSummary(
    t["thread"], t["timestamp"], t["date_relative"],
    something(get(t, "authors", nothing), ""), something(get(t, "subject", nothing), ""),
    t["matched"], t["total"], String.(t["tags"]))

"""
A file attached to a message: its MIME part number, name, type and size.
"""
struct Attachment
    part::Int
    filename::String
    content_type::String
    size::Int
end

"""
One message: its headers, the plain-text and HTML bodies (`""` when it has
none) and its attachments.
"""
struct Message
    id::String
    timestamp::Int
    date::String
    from::String
    to::String
    cc::String
    subject::String
    tags::Vector{String}
    text::String
    html::String
    attachments::Vector{Attachment}
end

"""
A thread's messages, oldest first.
"""
struct Conversation
    id::String
    messages::Vector{Message}
end

# The bodies and attachments found walking a message's MIME tree.
mutable struct Body
    text::String
    html::String
    attachments::Vector{Attachment}
end

function Message(m::AbstractDict)
    headers = m["headers"]
    header(name) = String(something(get(headers, name, nothing), ""))
    body = Body("", "", Attachment[])
    for p in m["body"]
        collect_parts!(body, p)
    end
    return Message(m["id"], m["timestamp"], m["date_relative"], header("From"), header("To"),
                   header("Cc"), header("Subject"), String.(m["tags"]),
                   body.text, body.html, body.attachments)
end

# The first plain-text and the first HTML part are the bodies; a part with a
# file name, or marked as an attachment, is an attachment. A forwarded message
# (message/rfc822) counts as an attachment too, under its subject.
function collect_parts!(body::Body, p::AbstractDict)
    type = lowercase(String(get(p, "content-type", "")))
    content = get(p, "content", nothing)
    filename = get(p, "filename", nothing)
    if type == "message/rfc822"
        push!(body.attachments, Attachment(p["id"], forwarded_name(content), type,
                                           get(p, "content-length", 0)))
    elseif content isa AbstractVector
        foreach(c -> collect_parts!(body, c), content)
    elseif filename !== nothing || get(p, "content-disposition", "") == "attachment"
        push!(body.attachments, Attachment(p["id"], something(filename, "part $(p["id"])"), type,
                                           decoded_size(p, content)))
    elseif type == "text/plain" && isempty(body.text) && content isa AbstractString
        body.text = content
    elseif type == "text/html" && isempty(body.html) && content isa AbstractString
        body.html = content
    end
    return body
end

# notmuch reports the ENCODED length: base64 is a third longer than the file.
function decoded_size(p::AbstractDict, content)
    content isa AbstractString && return sizeof(content)
    n = get(p, "content-length", 0)
    return lowercase(get(p, "content-transfer-encoding", "")) == "base64" ? div(3n, 4) : n
end

# notmuch shows a forwarded message's headers inside the part.
function forwarded_name(content)
    content isa AbstractVector && !isempty(content) || return "forwarded message.eml"
    subject = get(get(first(content), "headers", Dict()), "Subject", "")
    return isempty(subject) ? "forwarded message.eml" : subject * ".eml"
end
