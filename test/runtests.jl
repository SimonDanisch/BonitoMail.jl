using Test
using Bonito
using BonitoMail
using BonitoMail: split_quote, sender, initials, linkify, command, collect_messages!, part_url,
                  mail_document, decoded_size, term
using JSON

# Made-up notmuch output (`notmuch show --format=json --format-version=5`), in
# the shapes real mail takes: a reply quoting its history, HTML with a PDF and
# a calendar file, a forwarded message, and an excluded (spam) reply.
const SHOW = """
[[[{"id": "first@example.com", "match": true, "excluded": false, "filename": ["/m/1"],
    "timestamp": 1700000000, "date_relative": "Nov. 14", "tags": ["inbox"],
    "headers": {"Subject": "Workshop", "From": "Ada Lovelace <ada@example.com>",
                "To": "me@example.com", "Date": "Tue, 14 Nov 2023 22:13:20 +0000"},
    "body": [{"id": 1, "content-type": "multipart/alternative", "content": [
        {"id": 2, "content-type": "text/plain", "content": "Will you come?\\n\\nAda\\n"},
        {"id": 3, "content-type": "text/html", "content": "<p>Will you come?</p>"}]}]},
   [[{"id": "second@example.com", "match": true, "excluded": false, "filename": ["/m/2"],
      "timestamp": 1700100000, "date_relative": "Nov. 16", "tags": ["inbox", "attachment"],
      "headers": {"Subject": "Re: Workshop", "From": "\\"Lovelace, Ada\\" <ada@example.com>",
                  "To": "me@example.com", "Cc": "bob@example.com"},
      "body": [{"id": 1, "content-type": "multipart/mixed", "content": [
          {"id": 2, "content-type": "text/html", "content": "<b>Tickets attached</b>"},
          {"id": 3, "content-type": "application/pdf", "content-disposition": "attachment",
           "filename": "ticket.pdf", "content-transfer-encoding": "base64", "content-length": 400},
          {"id": 4, "content-type": "text/calendar", "content-disposition": "attachment",
           "filename": "event.ics", "content": "BEGIN:VCALENDAR"},
          {"id": 5, "content-type": "message/rfc822", "content-length": 900,
           "content": [{"headers": {"Subject": "Booking"}, "body": []}]}]}]},
     [[{"id": "spam@example.com", "match": false, "excluded": true, "filename": ["/m/3"],
        "timestamp": 1700050000, "date_relative": "Nov. 15", "tags": ["spam"],
        "headers": {"Subject": "Re: Workshop", "From": "x@spam.example"},
        "body": [{"id": 1, "content-type": "text/plain", "content": "buy"}]}, []]]]]]]]
"""

const SEARCH = """
[{"thread": "0000000000000001", "timestamp": 1700100000, "date_relative": "Nov. 16",
  "matched": 2, "total": 3, "authors": "Ada Lovelace", "subject": "Workshop",
  "query": ["id:first@example.com", null], "tags": ["attachment", "inbox", "unread"]}]
"""

@testset "BonitoMail" begin
    @testset "thread summaries" begin
        t = only(ThreadSummary.(JSON.parse(SEARCH)))
        @test t.id == "0000000000000001"
        @test (t.matched, t.total) == (2, 3)
        @test "unread" in t.tags
    end

    @testset "messages from a thread tree" begin
        messages = collect_messages!(Message[], only(JSON.parse(SHOW)))
        # The excluded (spam) reply stays out; its siblings and parents stay in.
        @test [m.id for m in messages] == ["first@example.com", "second@example.com"]
        first_msg, reply = messages
        @test first_msg.text == "Will you come?\n\nAda\n"
        @test first_msg.html == "<p>Will you come?</p>"
        @test isempty(first_msg.attachments)
        @test reply.text == ""
        @test reply.html == "<b>Tickets attached</b>"
        @test reply.cc == "bob@example.com"
        @test [a.filename for a in reply.attachments] == ["ticket.pdf", "event.ics", "Booking.eml"]
        # notmuch reports base64's encoded length; the chip shows the file's.
        @test reply.attachments[1].size == 300
        @test reply.attachments[2].size == sizeof("BEGIN:VCALENDAR")
        @test reply.attachments[3].content_type == "message/rfc822"
    end

    @testset "quoted history" begin
        gmail = "Sounds good!\n\nOn Tue, 18 Aug 2026 at 09:46, Simon <s@example.com> wrote:\n\n> Dear Ada,\n> yes"
        body, quoted = split_quote(gmail)
        @test body == "Sounds good!"
        @test startswith(quoted, "On Tue")
        # Gmail wraps a long attribution over two lines.
        wrapped = "Yes.\n\nOn Mon, Oct 20, 2026 at 5:12 PM Ada Lovelace <\nada@example.com> wrote:\n> hi"
        @test split_quote(wrapped)[1] == "Yes."
        german = "Gerne.\n\nAm Di., 18. Aug. 2026 um 09:46 Uhr schrieb Ada <a@example.com>:\n> Hallo"
        @test split_quote(german)[1] == "Gerne."
        french = "Oui.\n\nLe mar. 18 août 2026 à 09:46, Ada <a@example.com> a écrit :\n> Salut"
        @test split_quote(french)[1] == "Oui."
        # Reads like an attribution, but no quote follows: it is the message.
        prose = "Hallo,\n\nAm Freitag schrieb ich dir:\nwir treffen uns um acht."
        @test split_quote(prose) == (prose, "")
        outlook = "Thanks\n\nFrom: Ada <a@example.com>\nSent: Monday\nTo: me\nSubject: x\n\nold"
        @test split_quote(outlook)[1] == "Thanks"
        bottom = "Agreed.\n\n> earlier point\n>\n> more"
        @test split_quote(bottom) == ("Agreed.", "> earlier point\n>\n> more")
        # A quote with an answer under it is a conversation, not history.
        inline = "> question?\nanswer\n> another?\nanother answer"
        @test split_quote(inline) == (inline, "")
        # A message that is all quote stays whole.
        @test split_quote("> only a quote")[1] == "> only a quote"
        @test split_quote("plain\n") == ("plain", "")
    end

    @testset "senders and avatars" begin
        @test sender("Ada Lovelace <ada@example.com>") == ("Ada Lovelace", "ada@example.com")
        @test sender("\"Lovelace, Ada\" <ada@example.com>") == ("Lovelace, Ada", "ada@example.com")
        @test sender("<ada@example.com>") == ("ada@example.com", "ada@example.com")
        @test sender("ada@example.com") == ("ada@example.com", "ada@example.com")
        @test initials("Gokulanand Iyer") == "GI"
        @test initials("noreply@x.com") == "N"
        @test initials("Ada Byron Lovelace") == "AB"
        @test initials("123") == "?"
    end

    @testset "links in text" begin
        nodes = linkify("see https://example.com/a?b=1. and http://x.org)")
        links = [n for n in nodes if !(n isa AbstractString)]
        @test length(links) == 2
        @test occursin("href=\"https://example.com/a?b=1\"", string(links[1]))
        @test occursin("href=\"http://x.org\"", string(links[2]))
        @test join(n isa AbstractString ? n : "<a>" for n in nodes) == "see <a>. and <a>)"
        @test linkify("no links here") == ["no links here"]
        @test linkify("ünïcödé https://ex.com ä") isa Vector
    end

    @testset "HTML mail document" begin
        doc = mail_document("""<meta http-equiv="refresh" content="0;url=https://evil"><p>hi</p>""")
        @test !occursin("refresh", doc)
        @test occursin("default-src 'none'", doc)
        @test occursin("<p>hi</p>", doc)
    end

    @testset "commands" begin
        # Every argument survives the remote shell: run the remote "shell" as
        # `sh -c` and print the arguments back.
        args = ["printf", "%s\\n", "from:\"Ada Lovelace\"", "it's", "a b", "\$HOME", "(x or y)"]
        @test readlines(command(Remote(`sh -c`), args)) == args[3:end]
        @test command(Local(), ["notmuch", "count"]) == `notmuch count`
        @test term("id", "a\"b@x") == "id:\"a\"\"b@x\""
    end

    @testset "attachment urls" begin
        m = collect_messages!(Message[], only(JSON.parse(SHOW)))[2]
        url = part_url(m, m.attachments[1])
        @test startswith(url, "/part/second%40example.com/3?")
        @test occursin("type=application%2Fpdf", url)
        @test occursin("name=ticket.pdf", url)
        m2 = match(r"^/part/([^/?]+)/(\d+)", url)
        @test m2 !== nothing && m2[2] == "3"
    end
end
