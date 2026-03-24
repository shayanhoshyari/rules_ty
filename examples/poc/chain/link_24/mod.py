from chain.link_23.mod import Item, create_item


class Item24(Item):
    def __init__(self, name: str, value: int, extra: str) -> None:
        super().__init__(name, value)
        self.extra = extra

    def full_describe(self) -> str:
        return self.describe() + " [" + self.extra + "]"


def make(name: str, value: int) -> Item24:
    return Item24(name, value, "link_24")
