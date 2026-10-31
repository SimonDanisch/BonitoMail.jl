# The mail client in one browser tab: saved searches and a search field, the
# threads of the current query, and the open conversation. Read-only.

"""
    MailApp(nm; searches = default_searches(nm), page = 50)

One tab of the mail client. `searches` are the saved searches in the sidebar,
`label => notmuch query`; the first one opens. The thread list loads `page`
threads at a time as it scrolls. Build one per browser session
(`Bonito.Server(nm)` does).
"""
struct MailApp
    nm::Notmuch
    searches::Vector{Pair{String,String}}
    query::Observable{String}
    problem::Observable{String}     # why the last query failed, or ""
    selected::Observable{String}    # the open thread's id, or ""
    total::Observable{String}       # "N threads", once counted
    threads::InfiniteList           # the threads of `query`
end

function MailApp(nm::Notmuch; searches = default_searches(nm), page::Integer = 50)
    query = Observable(last(first(searches)))
    problem, selected = Observable(""), Observable("")
    threads = InfiniteList(ThreadQuery(nm, query[], selected, problem);
                           chunk = page, window = 4page, class = "bm-threads")
    app = MailApp(nm, searches, query, problem, selected, Observable(""), threads)
    newest = search(nm, query[]; limit = 1)
    isempty(newest) || (selected[] = first(newest).id)
    count_threads!(app)
    on(query) do q
        problem[] = ""
        threads.source[] = ThreadQuery(nm, q, selected, problem)
        count_threads!(app)
    end
    return app
end

"""
    ThreadQuery(nm, query, selected, problem)

The threads matching `query`, newest first, as the source of the thread list
(`BonitoWidgets.InfiniteList`). The row of the `selected` thread is marked; a
query notmuch can't parse ends the list and says why in `problem`.
"""
struct ThreadQuery
    nm::Notmuch
    query::String
    selected::Observable{String}
    problem::Observable{String}
end

function BonitoWidgets.items(q::ThreadQuery, range::UnitRange{Int})
    try
        return search(q.nm, q.query; limit = length(range), offset = first(range) - 1)
    catch e
        e isa NotmuchError || rethrow()
        q.problem[] = e.message
        return ThreadSummary[]
    end
end

BonitoWidgets.row(q::ThreadQuery, t::ThreadSummary) = thread_row(t, t.id == q.selected[])

# The header's thread count. notmuch groups every matching message to count
# threads, seconds on a big query, so the count arrives after the list; one for
# a query no longer shown is dropped. A failing query has its reason shown by
# the list already.
function count_threads!(app::MailApp)
    query = app.query[]
    app.total[] = ""
    Base.errormonitor(@async begin
        n = try
            thread_count(app.nm, query)
        catch e
            e isa NotmuchError || rethrow()
            nothing
        end
        if n !== nothing && app.query[] == query
            app.total[] = n == 1 ? "1 thread" : "$n threads"
        end
    end)
    return
end

"""
    default_searches(nm; inbox = "folder:gmail/INBOX") -> Vector{Pair{String,String}}

Inbox, unread, sent (from any of the user's addresses), with attachments, and
all mail.
"""
function default_searches(nm::Notmuch; inbox::AbstractString = "folder:gmail/INBOX")
    me = join(("from:" * a for a in addresses(nm)), " or ")
    return ["Inbox" => inbox, "Unread" => "tag:unread and ($inbox)", "Sent" => "($me)",
            "Attachments" => "tag:attachment", "All mail" => "*"]
end

function Bonito.jsrender(session::Session, app::MailApp)
    search_field = DOM.input(; type = "search", class = "bm-search", value = app.query,
        placeholder = "notmuch query, Enter to search", spellcheck = "false",
        onkeydown = js"event => { if (event.key === 'Enter') $(app.query).notify(event.target.value); }")
    nav = DOM.nav(DOM.div("Mail"; class = "bm-brand"), search_field,
                  [nav_item(session, app, label, query) for (label, query) in app.searches];
                  class = "bm-nav")

    rowbox = DOM.div(app.threads; class = "bm-rowbox")
    head = DOM.div(DOM.span(app.total), DOM.span(app.problem; class = "bm-problem");
                   class = "bm-list-head")
    list = DOM.section(head, rowbox,
                       js"$(MAIL_LIB).then(lib => new lib.ThreadList($(rowbox), $(app.selected)))";
                       class = "bm-list")

    # One renderable for every state (placeholder, conversation, error), so the
    # Observable is `Any` from the start.
    open = Observable{Any}(conversation_view(app, app.selected[]))
    on(id -> open[] = conversation_view(app, id), session, app.selected)
    conv = DOM.main(open; class = "bm-conv")

    return Bonito.jsrender(session, DOM.div(Theme(), BUTTON_STYLES, MAIL_STYLES, nav, list, conv;
                                            class = "bm-app"))
end

function nav_item(session::Session, app::MailApp, label::AbstractString, query::AbstractString)
    unread = thread_count(app.nm, "($query) and tag:unread")
    class = map(q -> q == query ? "bm-nav-item bm-active" : "bm-nav-item", session, app.query)
    return DOM.button(DOM.span(label), DOM.span(unread == 0 ? "" : string(unread); class = "bm-nav-count");
                      type = "button", class, title = query,
                      onclick = js"event => $(app.query).notify($(query))")
end

function conversation_view(app::MailApp, id::AbstractString)
    isempty(id) && return DOM.div("Select a conversation"; class = "bm-placeholder")
    try
        return conversation(app.nm, id)
    catch e
        e isa NotmuchError || rethrow()
        return DOM.div(e.message; class = "bm-problem bm-placeholder")
    end
end
