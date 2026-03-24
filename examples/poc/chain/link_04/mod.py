from chain.link_03.mod import Item, create_item


class Item04(Item):
    def __init__(self, name: str, value: int, extra: str) -> None:
        super().__init__(name, value)
        self.extra = extra

    def full_describe(self) -> str:
        return self.describe() + " [" + self.extra + "]"


def make(name: str, value: int) -> Item04:
    return Item04(name, value, "link_04")
