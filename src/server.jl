# Serving the app: one MailApp per browser tab, and attachments over HTTP.

"""
    PartRoute(nm)

Serves `/part/<message id>/<part>?type=…&name=…`: the bytes of an attachment.
Pictures display inline, everything else downloads.
"""
struct PartRoute
    nm::Notmuch
end

function Bonito.HTTPServer.apply_handler(route::PartRoute, context)
    id, number = HTTP.unescapeuri(context.match[1]), parse(Int, context.match[2])
    params = HTTP.queryparams(HTTP.URI(context.request.target))
    type = get(params, "type", "application/octet-stream")
    name = get(params, "name", "attachment")
    bytes = try
        part(route.nm, id, number)
    catch e
        e isa NotmuchError || rethrow()
        return HTTP.Response(404, e.message)
    end
    disposition = type in PREVIEW_TYPES ? "inline" : "attachment"
    return HTTP.Response(200, [
        "Content-Type" => type,
        "Content-Disposition" => "$disposition; filename*=UTF-8''$(HTTP.escapeuri(name))",
        # The sender's content: never sniffed into something else, and never a
        # script running on the app's origin.
        "X-Content-Type-Options" => "nosniff",
        "Content-Security-Policy" => "sandbox",
    ], bytes)
end

"""
    Bonito.Server(nm::Notmuch; host = "127.0.0.1", port = 8730, searches = default_searches(nm))

The mail client for the notmuch database `nm`, at `http://host:port/`.

```julia
nm = Notmuch(Remote(`ssh -o ControlPath=/tmp/cc-ssh-%C server`),
             "/home/server/bonitomail/notmuch-config")
server = Bonito.Server(nm)
```
"""
function Bonito.Server(nm::Notmuch; host::AbstractString = "127.0.0.1", port::Integer = 8730,
                       searches = default_searches(nm))
    app = App(; title = "Mail") do
        MailApp(nm; searches)
    end
    server = Bonito.Server(app, host, port)
    route!(server, r"^/part/([^/?]+)/(\d+)" => PartRoute(nm))
    return server
end
