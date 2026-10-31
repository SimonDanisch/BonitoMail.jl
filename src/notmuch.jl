# How the app reaches the mail: the notmuch command line with JSON output, run
# on this machine or over SSH. The same code serves the app next to the mail
# (on the server) and a prototype anywhere that can SSH there.

"""
    Local()

Run `notmuch` on this machine.
"""
struct Local end

"""
    Remote(ssh::Cmd)

Run `notmuch` through `ssh`, e.g. `Remote(\`ssh -o ControlPath=/tmp/cc-ssh-%C server\`)`.
With a multiplexed connection (`ControlMaster`) a query takes a few tens of
milliseconds.
"""
struct Remote
    ssh::Cmd
end

command(::Local, args::Vector{String}) = Cmd(args)
# ssh hands the remote shell ONE string, so every argument is quoted for it.
command(r::Remote, args::Vector{String}) = `$(r.ssh) $(Base.shell_escape_posixly(args...))`

"""
    Notmuch(host, config)

A notmuch database: where `notmuch` runs (`Local()` or `Remote(ssh)`) and the
path of the config file it reads there.
"""
struct Notmuch{H}
    host::H
    config::String
end

"""
    NotmuchError(message)

`notmuch` exited with an error, e.g. on a query it can't parse. `message` is
what it printed.
"""
struct NotmuchError <: Exception
    message::String
end
Base.showerror(io::IO, e::NotmuchError) = print(io, "notmuch: ", e.message)

"Run `notmuch args...` against `nm` and return its output."
function notmuch(nm::Notmuch, args::AbstractString...)
    cmd = command(nm.host, String["notmuch", "--config=$(nm.config)", args...])
    out, err = IOBuffer(), IOBuffer()
    process = run(pipeline(ignorestatus(cmd); stdout = out, stderr = err))
    success(process) || throw(NotmuchError(strip(String(take!(err)))))
    return take!(out)
end

# A query term matching `value` exactly: quoted, inner quotes doubled.
term(prefix::AbstractString, value::AbstractString) =
    string(prefix, ":\"", replace(value, "\"" => "\"\""), "\"")

# notmuch reads an empty query as an error; the UI means "everything".
query_or_all(query::AbstractString) = isempty(strip(query)) ? "*" : String(query)

"""
    search(nm, query; limit = 100, offset = 0) -> Vector{ThreadSummary}

The threads matching `query`, newest first.
"""
function search(nm::Notmuch, query::AbstractString; limit::Integer = 100, offset::Integer = 0)
    json = notmuch(nm, "search", "--format=json", "--format-version=5", "--sort=newest-first",
                   "--limit=$limit", "--offset=$offset", "--", query_or_all(query))
    return ThreadSummary[ThreadSummary(t) for t in JSON.parse(String(json))]
end

"""
    thread_count(nm, query) -> Int

How many threads match `query`.
"""
thread_count(nm::Notmuch, query::AbstractString) =
    parse(Int, String(notmuch(nm, "count", "--output=threads", "--", query_or_all(query))))

"""
    conversation(nm, thread_id) -> Conversation

Every message of a thread, oldest first, with its text, HTML and attachments.
"""
function conversation(nm::Notmuch, thread::AbstractString)
    json = notmuch(nm, "show", "--format=json", "--format-version=5", "--entire-thread=true",
                   "--include-html", "--", "thread:" * thread)
    messages = Message[]
    # A list of threads, each a list of `[message, replies]` pairs.
    for pairs in JSON.parse(String(json))
        collect_messages!(messages, pairs)
    end
    sort!(messages; by = m -> m.timestamp)
    return Conversation(String(thread), messages)
end

function collect_messages!(messages::Vector{Message}, pairs::AbstractVector)
    for (message, replies) in pairs
        # The rest of the thread comes with `--entire-thread`, including what the
        # search excludes (spam, deleted): those stay hidden here too.
        get(message, "excluded", false) || push!(messages, Message(message))
        collect_messages!(messages, replies)
    end
    return messages
end

"""
    part(nm, message_id, part) -> Vector{UInt8}

The decoded content of MIME part `part` of a message: an attachment's bytes.
"""
part(nm::Notmuch, message::AbstractString, part::Integer) =
    notmuch(nm, "show", "--format=raw", "--part=$part", "--", term("id", message))

"""
    addresses(nm) -> Vector{String}

The user's own addresses, from the notmuch config.
"""
function addresses(nm::Notmuch)
    primary = strip(String(notmuch(nm, "config", "get", "user.primary_email")))
    others = split(String(notmuch(nm, "config", "get", "user.other_email")), '\n'; keepempty = false)
    return String[primary; strip.(others)]
end
