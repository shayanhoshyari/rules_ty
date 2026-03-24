class Item:
    def __init__(self, name: str, value: int) -> None:
        self.name = name
        self.value = value

    def describe(self) -> str:
        return f"{self.name}: {self.value}"


def create_item(name: str, value: int) -> Item:
    return Item(name, value)
