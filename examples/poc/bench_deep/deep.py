from chain.link_25.mod import Item25, make


def deep_result() -> str:
    item: Item25 = make("final", 42)
    return item.full_describe()
