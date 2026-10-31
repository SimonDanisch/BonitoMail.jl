# How the mail looks: thread rows, the conversation, messages, HTML mail and
# attachments.

const MAIL_LIB = Bonito.ES6Module(joinpath(@__DIR__, "..", "assets", "mail.js"))

# Images an attachment chip previews, and the route serves inline. Everything
# else downloads.
const PREVIEW_TYPES = ("image/png", "image/jpeg", "image/gif", "image/webp")

function thread_row(t::ThreadSummary, active::Bool)
    class = "bm-thread" * ("unread" in t.tags ? " bm-unread" : "") * (active ? " bm-active" : "")
    return DOM.div(
        DOM.div(DOM.span(t.authors; class = "bm-authors"), DOM.span(t.date; class = "bm-date");
                class = "bm-row-top"),
        DOM.div(DOM.span(isempty(t.subject) ? "(no subject)" : t.subject; class = "bm-subject"),
                "attachment" in t.tags ? DOM.span("📎"; class = "bm-clip", title = "Attachments") : nothing,
                t.total > 1 ? DOM.span(string(t.total); class = "bm-count") : nothing;
                class = "bm-row-bottom");
        class, dataThread = t.id)
end

function Bonito.jsrender(session::Session, c::Conversation)
    isempty(c.messages) && return Bonito.jsrender(session, DOM.div("Nothing to show"; class = "bm-placeholder"))
    subject = first(c.messages).subject
    people = unique(first(sender(m.from)) for m in c.messages)
    meta = string(length(c.messages), length(c.messages) == 1 ? " message" : " messages",
                  " · ", join(people, ", "))
    return Bonito.jsrender(session, DOM.div(
        DOM.h1(isempty(subject) ? "(no subject)" : subject; class = "bm-conv-subject"),
        DOM.div(meta; class = "bm-conv-meta"),
        c.messages;
        class = "bm-conv-inner"))
end

function Bonito.jsrender(session::Session, m::Message)
    name, address = sender(m.from)
    head = DOM.div(DOM.span(name; class = "bm-from", title = address),
                   DOM.span("to " * m.to; class = "bm-to", title = m.cc == "" ? m.to : "$(m.to), cc $(m.cc)"),
                   DOM.span(m.date; class = "bm-date", title = Libc.strftime("%a %d %b %Y, %H:%M", m.timestamp));
                   class = "bm-msg-head")
    return Bonito.jsrender(session, DOM.div(
        avatar(name, address),
        DOM.div(head, message_body(m), attachments(m); class = "bm-msg-main");
        class = "bm-msg", dataMessage = m.id))
end

# Plain text when the message has it, with the quoted history folded away and
# the formatted version one click away. HTML only when there is no text.
function message_body(m::Message)
    isempty(m.text) && isempty(m.html) && return DOM.div("(no text)"; class = "bm-placeholder")
    isempty(m.text) && return MailFrame(m.html)
    body, quoted = split_quote(m.text)
    return DOM.div(
        DOM.div(linkify(body); class = "bm-text"),
        isempty(quoted) ? nothing :
            DOM.details(DOM.summary("···"; title = "Show quoted text"),
                        DOM.div(linkify(quoted); class = "bm-text bm-quoted"); class = "bm-quote"),
        isempty(m.html) ? nothing :
            DOM.details(DOM.summary("Formatted"; title = "The message as its sender formatted it"),
                        MailFrame(m.html); class = "bm-formatted"))
end

# Text with its web addresses as links.
function linkify(text::AbstractString)
    nodes = Any[]
    from = firstindex(text)
    for m in eachmatch(r"https?://[^\s<>\"]*[^\s<>\".,;:!?)\]']", text)
        m.offset > from && push!(nodes, text[from:prevind(text, m.offset)])
        push!(nodes, DOM.a(m.match; href = m.match, target = "_blank", rel = "noopener noreferrer"))
        from = m.offset + ncodeunits(m.match)
    end
    from <= ncodeunits(text) && push!(nodes, text[from:end])
    return nodes
end

function avatar(name::AbstractString, address::AbstractString)
    hue = Int(hash(lowercase(address)) % 360)
    return DOM.div(initials(name); class = "bm-avatar", title = address,
                   style = Styles("background" => "hsl($hue, 45%, 48%)"))
end

"""
    MailFrame(html)

An HTML mail in a sandboxed frame: no scripts, no forms, no requests (remote
pictures stay out, so do trackers), links open in a new tab. It grows to its
content's height.
"""
struct MailFrame
    html::String
end

function Bonito.jsrender(session::Session, f::MailFrame)
    frame = DOM.iframe(; srcdoc = mail_document(f.html), class = "bm-frame", title = "Formatted message",
                       sandbox = "allow-same-origin allow-popups allow-popups-to-escape-sandbox",
                       referrerpolicy = "no-referrer")
    return Bonito.jsrender(session, DOM.div(frame, js"$(MAIL_LIB).then(lib => lib.fitFrame($(frame)))"))
end

# The mail as a document of its own. Same origin is what lets the app measure
# it, and is safe because the sandbox runs no script. The policy blocks every
# request; a refresh tag, which could still navigate the frame, goes.
function mail_document(html::AbstractString)
    clean = replace(html, r"<meta[^>]*http-equiv\s*=\s*[\"']?refresh[^>]*>"i => "")
    return """<!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:">
        <base target="_blank">
        <style>body { margin: 0; padding: 8px; font-family: system-ui, sans-serif; font-size: 14px; overflow-wrap: anywhere; }
        img { max-width: 100%; height: auto; }</style>
        </head><body>$clean</body></html>"""
end

function attachments(m::Message)
    isempty(m.attachments) && return nothing
    chips = map(m.attachments) do a
        url = part_url(m, a)
        DOM.a(a.content_type in PREVIEW_TYPES ? DOM.img(; src = url, loading = "lazy", alt = a.filename) : nothing,
              DOM.span(a.filename; class = "bm-att-name", title = a.filename),
              DOM.span(string(a.content_type, " · ", format_size(a.size)); class = "bm-att-size");
              href = url, target = "_blank", rel = "noopener", class = "bm-att")
    end
    return DOM.div(chips; class = "bm-atts")
end

function format_size(bytes::Integer)
    bytes < 1024 && return "$bytes B"
    bytes < 1024^2 && return "$(round(bytes / 1024; digits = 1)) KB"
    return "$(round(bytes / 1024^2; digits = 1)) MB"
end

# Where the browser fetches an attachment (`PartRoute`). The type and name ride
# along, so serving it takes one notmuch call.
part_url(m::Message, a::Attachment) = string(
    "/part/", HTTP.escapeuri(m.id), "/", a.part,
    "?type=", HTTP.escapeuri(a.content_type), "&name=", HTTP.escapeuri(a.filename))
