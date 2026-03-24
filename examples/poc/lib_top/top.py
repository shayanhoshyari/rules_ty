from lib_mid.mid import greet_twice, multiply


def main_greeting(name: str) -> str:
    result = greet_twice(name)
    total = multiply(3, 4)
    return f"{result} (total={total})"
