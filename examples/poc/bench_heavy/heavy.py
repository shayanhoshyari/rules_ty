import numpy as np
import pandas as pd


def compute_stats(data: list[float]) -> dict[str, float]:
    arr: np.ndarray = np.array(data)
    df: pd.DataFrame = pd.DataFrame({"values": data})
    return {
        "mean": float(arr.mean()),
        "std": float(arr.std()),
        "median": float(df["values"].median()),
        "sum": float(df["values"].sum()),
    }
