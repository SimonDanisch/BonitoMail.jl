# Plain-text mail: separating what a sender wrote from the history they quote,
# and reading a "Name <address>" header.

"""
    split_quote(text) -> (body, quoted)

Split a plain-text message into what the sender wrote and the quoted history
under it, so a conversation shows each reply once. The history starts at an
attribution ("On … wrote:", "Am … schrieb …:", wrapped onto two lines or not),
an "Original Message" separator, an Outlook header block ("From:" followed by
"Sent:"), or a trailing block of `>` lines. Replies quoted in between stay as
they are. A message that is ALL quote is returned whole.
"""
function split_quote(text::AbstractString)
    lines = split(text, '\n')
    for i in eachindex(lines)
        if (attribution(lines, i) && quote_follows(lines, i)) || separator(lines[i]) ||
           outlook_header(lines, i) || quoted_tail(lines, i)
            body = rstrip(join(lines[1:i-1], '\n'))
            isempty(body) && break
            return (String(body), String(join(lines[i:end], '\n')))
        end
    end
    return (String(rstrip(text)), "")
end

# An attribution line, or one wrapped over two lines (Gmail breaks long ones).
function attribution(lines, i)
    # English ends in "wrote:", German puts the sender between "schrieb" and
    # the colon, French writes "a écrit :".
    pattern = r"^\s*(On|Am|Le)\s.*(\bwrote\s*:|\bschrieb\b.*:|\sécrit\s*:)\s*$"
    occursin(pattern, lines[i]) && return true
    i < lastindex(lines) || return false
    occursin(r"^\s*(On|Am|Le)\s", lines[i]) || return false
    return occursin(pattern, string(rstrip(lines[i]), " ", lstrip(lines[i+1])))
end

# An attribution is followed by the quote it introduces; a sentence that merely
# reads like one ("Am Freitag schrieb ich:") is not.
quote_follows(lines, i) = any(l -> startswith(l, '>'), lines[i+1:min(i + 4, end)])

separator(line) = occursin(r"^\s*-{2,}\s*(Original Message|Ursprüngliche Nachricht)\s*-{2,}"i, line)

outlook_header(lines, i) = occursin(r"^\s*(From|Von):\s", lines[i]) &&
    any(l -> occursin(r"^\s*(Sent|Gesendet|Date|Datum):\s", l), lines[i+1:min(i + 3, end)])

# From line `i` on, every non-empty line is quoted.
quoted_tail(lines, i) = startswith(lines[i], '>') &&
    all(l -> isempty(strip(l)) || startswith(l, '>'), lines[i:end])

"""
    sender(header) -> (name, address)

The display name and address of a `"Name" <address>` header. Without a name,
the address stands in for it.
"""
function sender(header::AbstractString)
    m = match(r"^\s*\"?(.*?)\"?\s*<([^>]+)>\s*$", header)
    m === nothing && return (String(strip(header)), String(strip(header)))
    name, address = strip(m[1]), strip(m[2])
    return (String(isempty(name) ? address : name), String(address))
end

"""
    initials(name) -> String

Up to two initials for an avatar: "Gokulanand Iyer" is "GI", "noreply@x.com" is "N".
"""
function initials(name::AbstractString)
    words = split(replace(name, r"@.*$" => ""), r"[\s._-]+"; keepempty = false)
    letters = [uppercase(first(w)) for w in words if isletter(first(w))]
    return isempty(letters) ? "?" : String(letters[1:min(2, end)])
end
