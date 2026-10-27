"""In-process conversation event fan-out for WebSocket subscribers.

Chat mutations are synchronous and may run in FastAPI's thread pool, while
subscribers live on the server event loop. Publishing therefore hands each
queue a thread-safe callback through ``call_soon_threadsafe``. A slow or full
subscriber queue is allowed to drop events; the durable event log remains the
authoritative catch-up path through the polling endpoint.
"""

from __future__ import annotations

import asyncio
import threading
from dataclasses import dataclass

from ..models.chat import ConversationEvent

_QUEUE_SIZE = 200


@dataclass(frozen=True, slots=True)
class _Subscription:
    queue: asyncio.Queue[ConversationEvent]
    loop: asyncio.AbstractEventLoop


class ConversationBroadcaster:
    def __init__(self) -> None:
        self._subscriptions: dict[str, set[_Subscription]] = {}
        self._lock = threading.RLock()

    def subscribe(
        self,
        conversation_id: str,
    ) -> asyncio.Queue[ConversationEvent]:
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[ConversationEvent] = asyncio.Queue(
            maxsize=_QUEUE_SIZE
        )
        subscription = _Subscription(queue=queue, loop=loop)
        with self._lock:
            self._subscriptions.setdefault(conversation_id, set()).add(
                subscription
            )
        return queue

    def unsubscribe(
        self,
        conversation_id: str,
        queue: asyncio.Queue[ConversationEvent],
    ) -> None:
        with self._lock:
            subscriptions = self._subscriptions.get(conversation_id)
            if not subscriptions:
                return
            for subscription in tuple(subscriptions):
                if subscription.queue is queue:
                    subscriptions.discard(subscription)
            if not subscriptions:
                self._subscriptions.pop(conversation_id, None)

    def publish(self, event: ConversationEvent) -> None:
        with self._lock:
            subscriptions = tuple(
                self._subscriptions.get(event.conversation_id, ())
            )
        for subscription in subscriptions:
            try:
                subscription.loop.call_soon_threadsafe(
                    self._deliver,
                    subscription.queue,
                    event,
                )
            except RuntimeError:
                # The subscriber's loop has already closed.
                continue

    @staticmethod
    def _deliver(
        queue: asyncio.Queue[ConversationEvent],
        event: ConversationEvent,
    ) -> None:
        try:
            queue.put_nowait(event)
        except asyncio.QueueFull:
            return
