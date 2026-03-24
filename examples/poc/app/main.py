import numpy as np
import requests

from lib_top.top import main_greeting


def run() -> None:
    greeting: str = main_greeting("world")
    print(greeting)

    arr: np.ndarray = np.array([1, 2, 3])
    print(f"Array sum: {arr.sum()}")

    resp: requests.Response = requests.get("https://httpbin.org/get")
    print(f"Status: {resp.status_code}")


if __name__ == "__main__":
    run()
