"""Storage-neutral transaction hooks for the service layer.

The in-memory backend uses a no-op scope. The PostgreSQL backend passes
``Database.transaction`` so a service method can make several repository calls
commit or roll back together.
"""

from __future__ import annotations

from collections.abc import Callable
from contextlib import AbstractContextManager, nullcontext

TransactionFactory = Callable[[], AbstractContextManager[None]]


def no_transaction() -> AbstractContextManager[None]:
    return nullcontext()
