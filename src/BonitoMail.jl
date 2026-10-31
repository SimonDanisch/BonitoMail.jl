"""
A mail client in Bonito, on top of notmuch.

Read-only for now: search, thread list, conversations, attachments.
"""
module BonitoMail

using Bonito
using Bonito: Session, Styles, CSS, route!
using BonitoWidgets
using BonitoWidgets: Theme, BUTTON_STYLES, InfiniteList
using HTTP
using JSON
using Observables

include("model.jl")
include("notmuch.jl")
include("text.jl")
include("styles.jl")
include("views.jl")
include("app.jl")
include("server.jl")

export Notmuch, Local, Remote, NotmuchError
export search, thread_count, conversation, part, addresses
export ThreadSummary, Message, Attachment, Conversation
export MailApp, ThreadQuery, MailFrame, default_searches

end
