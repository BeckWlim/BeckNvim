from abc import ABC, abstractmethod


class Repository(ABC):
    @abstractmethod
    def save(self, value: str) -> None: ...


class SqlRepository(Repository):
    def save(self, value: str) -> None: ...


class CachedRepository(SqlRepository):
    def save(self, value: str) -> None: ...


class MemoryRepository(Repository):
    async def save(self, value: str) -> None: ...
