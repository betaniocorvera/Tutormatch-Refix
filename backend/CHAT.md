# Requests and chat

Phase 4 turns the prototype's request cards, inbox, accepted-only thread, media,
session proposals, calls, read receipts, and unread dots into server state.

A request and its conversation are one aggregate. The product keeps exactly one
conversation per pair of people, so `request_id` and `conversation_id` are the
same id. The request status is also the conversation status:

```text
pending ──accept──> accepted ──> messages, sessions, calls
   │
   └──decline──> declined ──new request──> pending
```

The initial request note is stored on the request and is also the first message.
A declined request can be asked again; reopening keeps the same aggregate and the
old thread stays readable.

## Request endpoints

All endpoints require a bearer access token.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/requests` | Create a request: `{counterpart_id, subject, note}` |
| `GET` | `/requests` | List your requests; optional `direction` (`all`, `sent`, `received`) and `status` (`pending`, `accepted`, `declined`) |
| `GET` | `/requests/{id}` | One request summary |
| `POST` | `/requests/{id}/accept` | Receiver accepts; optional `{note}` becomes a reply message |
| `POST` | `/requests/{id}/decline` | Receiver declines; required `{reason}` becomes a reply message |

A request can only be created when:

- the counterpart exists and is on the other side of the student/tutor pair;
- it is not a request to yourself;
- both profiles have all five matching answers;
- the subject is canonical and appears in both profiles;
- there is no open (`pending` or `accepted`) conversation with that person.

The server computes the request's match score from the same weighted model as
`GET /matches`; the client does not send a score. Notes must be 12–1000
characters. The counterpart in every summary is a privacy-safe `PublicProfile`.

Only the person who received the request may accept or decline it. A requester
trying to answer their own request gets `403`. A non-participant gets `404`, not a
403, so the API does not reveal whether an id exists.

## Conversation endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/conversations` | Your inbox; optional `status` |
| `GET` | `/conversations/{id}` | Detail, read cursor, latest sequence |
| `GET` | `/conversations/{id}/messages` | Paginated messages |
| `POST` | `/conversations/{id}/messages` | Text message: `{text}` |
| `POST` | `/conversations/{id}/messages/image` | Multipart `file` |
| `POST` | `/conversations/{id}/messages/voice` | Multipart `file` + `duration_seconds` |
| `POST` | `/conversations/{id}/messages/voice-note` | Simulated voice note: `{duration_seconds}` |
| `GET` | `/conversations/{id}/messages/{message_id}/media` | Image or voice bytes |
| `POST` | `/conversations/{id}/sessions` | Propose a session: `{proposed_for}` |
| `POST` | `/conversations/{id}/sessions/{message_id}/respond` | `{state: accepted|declined}` |
| `POST` | `/conversations/{id}/calls` | Log a call event |
| `POST` | `/conversations/{id}/read` | Mark read, optionally `{through_sequence}` |
| `GET` | `/conversations/{id}/events` | Polling fallback and resume |

Only the two participants can read a conversation, its messages, its events, or
its media. Non-participants receive `404`. Sending text, images, voice notes,
session proposals, and call events requires `status=accepted`; a pending or
declined thread returns `409`.

## Message pagination

Messages have a per-conversation `sequence` starting at 1. `GET
/conversations/{id}/messages` accepts:

- `limit` — 1–100, default 30
- `before` — messages with a lower sequence, for loading older history
- `after` — messages with a higher sequence, for polling new messages

`before` and `after` are mutually exclusive. Results are always returned in
ascending sequence order. The response includes `has_more`, `next_before`,
`next_after`, `latest_sequence`, `read_through_sequence`, and `unread_count`.

The Flutter client should load the newest page first, then request `before` the
oldest loaded sequence to page backwards. When a WebSocket is unavailable, poll
`after=latest_sequence` instead.

## Message validation

- **Text**: trimmed, non-empty, at most 2000 characters.
- **Image**: at most 5 MB. Pillow decodes the upload, rejects unsupported,
  animated, tiny, or decompression-bomb inputs, applies EXIF orientation, strips
  metadata, and re-encodes as JPEG capped at 1024 px. The stored bytes are never
  the original upload.
- **Voice upload**: at most 10 MB, 1–300 seconds, and a known WAV, OGG, WebM,
  MP3, MP4/M4A, or AAC container signature. WAV duration is read from the file;
  compressed formats use the bounded form value. Declared audio MIME types must
  agree with the detected container.
- **Simulated voice note**: the existing prototype records only a duration, so
  `voice-note` accepts a bounded 1–300 second duration without bytes. Use the
  multipart `voice` endpoint when real audio is available.

Images and uploaded voice notes expose a private `media_url`. Fetching it
requires an access token and participant membership. Media is held in memory by
default; with `PERSIST_TO_FILE=true` it is written under `UPLOAD_DIR/chat`.

## Read receipts and unread counts

Each participant has a `last_read_sequence`. A message is read by its recipient
when that recipient's cursor is at or past the message's sequence. A message view
exposes `read_by_recipient`; the conversation detail exposes
`read_through_sequence`; summaries and message pages expose `unread_count`.

`POST /conversations/{id}/read` advances the caller's cursor to the latest
message by default. A supplied `through_sequence` is clamped to the latest
message, so a stale client cannot read into the future. Repeating a read at the
same cursor is a no-op and does not create another event. Reading does not change
`updated_at`, so an inbox does not jump to the top just because it was opened.

Sending a message marks it read for its sender. Accepting or declining a request
also marks the receiver's view of the pending thread as read.

## WebSocket and polling

Connect with:

```text
ws://127.0.0.1:8000/ws/conversations/{id}?token={access_token}&after={event_sequence}
```

The token may also be sent as an `Authorization: Bearer ...` header. The first
server frame is:

```json
{"type":"ready","conversation_id":"...","status":"accepted",
 "last_event_sequence":4,"read_through_sequence":2}
```

The server then replays durable events after `after` and pushes new events. A
`{"type":"ping"}` frame is sent every five seconds. Events use the same shape as
`GET /conversations/{id}/events`:

```json
{"sequence":5,"conversation_id":"...","type":"message_created",
 "actor_id":"...","created_at":"...","message":{...},
 "request_status":null,"read_through_sequence":null,"session_state":null}
```

Close codes are `4401` for a missing/invalid token, `4400` for an invalid cursor,
and `4404` for a missing conversation or non-participant. Sending stays on REST;
the socket is the push channel.

If the socket drops, call `GET /conversations/{id}/events?after={last_sequence}`
to catch up. Event types are `request_created`, `request_accepted`,
`request_declined`, `message_created`, `session_updated`, `call_logged`, and
`conversation_read`. Event sequences are independent of message sequences.

## Sessions and calls

Session proposals require an accepted conversation. `proposed_for` must be a
timezone-aware or naive datetime in the future and within the next year. The
proposal is a `session` message with `session_state=proposed`. Only the other
participant can respond, and only once; the answer is `accepted` or `declined`
and emits a `session_updated` event.

Call logging is simulated, not a media call. `POST /conversations/{id}/calls`
accepts `{kind: voice|video, connected: bool, duration_seconds}` and stores a
`call` message (`"Video call · 1:15"` or `"Missed call"`). A missed call must have
duration 0; the maximum is 3600 seconds. The event type is `call_logged`.

## Persistence

When `PERSIST_TO_FILE=true`, the JSON snapshot includes the `conversations`
repository: request state, messages, events, and read cursors. Chat media is
written under `UPLOAD_DIR/chat` with hashed filenames. Without persistence,
requests, messages, events, and media reset on restart.

## Status codes

| Code | Meaning |
| --- | --- |
| `401` | Missing or invalid access token |
| `403` | Participant tried to answer their own request or session proposal |
| `404` | Request/conversation/message/media not found, or not a participant |
| `409` | Open request already exists, request already answered, or chat locked |
| `413` | Image or voice upload too large |
| `422` | Invalid request, message, subject, time, call, or pagination |

## Flutter client notes

- Use the bearer access token on every REST request and pass it to the socket as
  the `token` query value (or an `Authorization` header).
- Open a conversation with `GET /conversations/{id}` and the newest message page,
  then call `POST /read`. Load older pages with `before`; do not re-query the
  match list for local text search.
- Keep the last event sequence and call `GET /conversations/{id}/events?after=...`
  after a socket drop or on a polling timer. Ignore `ping` frames.
- Send images as multipart `file`; send recorded audio as multipart `file` plus
  `duration_seconds`. The existing prototype's duration-only recorder can keep
  using the `voice-note` endpoint.
- Media URLs are private. Fetch them with the same authenticated API client and
  render the returned bytes; do not treat them as public web URLs.
- Sending stays on REST even while the WebSocket is open. The socket only
  delivers events, so a failed send should be retried through the REST client.
