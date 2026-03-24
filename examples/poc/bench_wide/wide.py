import click
import flask
import httpx
import numpy as np
import pandas as pd
import pydantic
import requests


def summary() -> str:
    parts: list[str] = [
        f"click {click.__version__}",
        f"flask {flask.__version__}",
        f"numpy {np.__version__}",
        f"pandas {pd.__version__}",
        f"pydantic {pydantic.__version__}",
        f"requests {requests.__version__}",
    ]
    return ", ".join(parts)


async def fetch(url: str) -> httpx.Response:
    async with httpx.AsyncClient() as client:
        return await client.get(url)
