from lib_base.base import greet, add


def greet_twice(name: str) -> str:
    return greet(name) + " " + greet(name)


def multiply(a: int, b: int) -> int:
    return add(a, 0) + add(b, 0)
