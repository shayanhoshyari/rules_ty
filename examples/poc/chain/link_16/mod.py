from chain.link_15.mod import Item, create_item


class Item16(Item):
    def __init__(self, name: str, value: int, extra: str) -> None:
        super().__init__(name, value)
        self.extra = extra

    def full_describe(self) -> str:
        return self.describe() + " [" + self.extra + "]"


def make(name: str, value: int) -> Item16:
    return Item16(name, value, "link_16")
