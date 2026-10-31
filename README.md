# BonitoMail

A mail client in Bonito on top of [notmuch](https://notmuchmail.org). Read-only
for now: saved searches, notmuch queries, an infinite-scrolling thread list, conversations with the
quoted history folded away, HTML mail in a sandboxed frame without remote
content, and attachments.

## Running it

The app talks to notmuch's command line, on this machine or over SSH:

```julia
using BonitoMail, Bonito

# Mail on another machine: open a multiplexed connection first
# (ssh -o ControlMaster=auto -o ControlPath=/tmp/cc-ssh-%C -o ControlPersist=8h server true).
nm = Notmuch(Remote(`ssh -o ControlPath=/tmp/cc-ssh-%C server`),
             "/home/server/bonitomail/notmuch-config")

# Mail here:
# nm = Notmuch(Local(), expanduser("~/bonitomail/notmuch-config"))

server = Bonito.Server(nm; port = 8730)   # http://127.0.0.1:8730/
```

The search field takes notmuch queries (`from:ada tag:unread`, `date:2026-10..`,
`tag:attachment and mimetype:application/pdf`); Enter runs them. The sidebar's
saved searches are `default_searches(nm)`, or pass your own as
`searches = ["Label" => "query", ...]`.

The index has to follow the Maildir: run `notmuch new` after every sync, or a
file renamed by the sync (a message read elsewhere) can't be opened.
