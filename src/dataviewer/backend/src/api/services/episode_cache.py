"""
LRU episode cache for parsed episode data.

Provides a fixed-capacity circular buffer that caches fully parsed
EpisodeData objects, avoiding repeated parquet/HDF5 reads and
numpy-to-JSON conversion on every episode request.
"""

from __future__ import annotations

import logging
from collections import OrderedDict
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ...models.datasources import EpisodeData

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class CacheStats:
    """Snapshot of cache performance metrics."""

    capacity: int
    size: int
    hits: int
    misses: int

    @property
    def hit_rate(self) -> float:
        total = self.hits + self.misses
        return self.hits / total if total > 0 else 0.0


@dataclass
class EpisodeCache:
    """
    LRU cache for parsed episode data.

    Stores up to *capacity* episodes keyed by ``(dataset_id, episode_index)``.
    When capacity is reached, the least-recently-used entry is evicted.
    A capacity of ``0`` disables caching (all operations become no-ops).
    """

    capacity: int = 32
    _entries: OrderedDict[tuple[str, int], EpisodeData] = field(
        default_factory=OrderedDict, init=False, repr=False,
    )
    _hits: int = field(default=0, init=False, repr=False)
    _misses: int = field(default=0, init=False, repr=False)

    @property
    def enabled(self) -> bool:
        return self.capacity > 0

    def get(self, dataset_id: str, episode_index: int) -> EpisodeData | None:
        """Retrieve a cached episode, promoting it to most-recently-used."""
        if not self.enabled:
            return None

        key = (dataset_id, episode_index)
        entry = self._entries.get(key)
        if entry is not None:
            self._entries.move_to_end(key)
            self._hits += 1
            return entry

        self._misses += 1
        return None

    def put(self, dataset_id: str, episode_index: int, data: EpisodeData) -> None:
        """Insert or update a cache entry, evicting the oldest if at capacity."""
        if not self.enabled:
            return

        key = (dataset_id, episode_index)
        if key in self._entries:
            self._entries.move_to_end(key)
            self._entries[key] = data
            return

        if len(self._entries) >= self.capacity:
            evicted_key, _ = self._entries.popitem(last=False)
            logger.debug("Episode cache evicted %s", evicted_key)

        self._entries[key] = data

    def invalidate(self, dataset_id: str, episode_index: int | None = None) -> int:
        """
        Remove cache entries.

        Args:
            dataset_id: Dataset to invalidate.
            episode_index: Specific episode to remove. When ``None``,
                           all episodes for the dataset are removed.

        Returns:
            Number of entries removed.
        """
        if not self.enabled:
            return 0

        if episode_index is not None:
            key = (dataset_id, episode_index)
            if key in self._entries:
                del self._entries[key]
                return 1
            return 0

        keys_to_remove = [k for k in self._entries if k[0] == dataset_id]
        for key in keys_to_remove:
            del self._entries[key]

        return len(keys_to_remove)

    def clear(self) -> None:
        """Remove all entries and reset counters."""
        self._entries.clear()
        self._hits = 0
        self._misses = 0

    def stats(self) -> CacheStats:
        """Return a snapshot of cache performance metrics."""
        return CacheStats(
            capacity=self.capacity,
            size=len(self._entries),
            hits=self._hits,
            misses=self._misses,
        )
