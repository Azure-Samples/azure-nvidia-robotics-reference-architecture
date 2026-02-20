"""Quick verification of converted LeRobot dataset."""

import numpy as np
import pandas as pd

df = pd.read_parquet("output/data/chunk-000/file-000.parquet")
print(f"Parquet: {len(df)} rows, columns: {list(df.columns)}")
print()

# Show first 3 frames
for i in range(3):
    row = df.iloc[i]
    state = np.array(row["observation.state"])
    action = np.array(row["action"])
    s_str = ", ".join(f"{v:+.4f}" for v in state)
    a_str = ", ".join(f"{v:+.4f}" for v in action)
    print(f"Frame {i}:")
    print(f"  state:  [{s_str}]")
    print(f"  action: [{a_str}]")
    print(f"  ep={row['episode_index']}, frame={row['frame_index']}, ts={row['timestamp']:.3f}")
    print()

# Stats
states = np.stack(df["observation.state"].values)
actions = np.stack(df["action"].values)
names = ["base", "shoulder", "elbow", "wrist1", "wrist2", "wrist3"]

print("State range:")
for j, n in enumerate(names):
    col = states[:, j]
    print(f"  {n:10s}: mean={col.mean():+.4f}  std={col.std():.4f}  min={col.min():+.4f}  max={col.max():+.4f}")

print()
print("Action (delta) range:")
for j, n in enumerate(names):
    col = actions[:, j]
    print(f"  {n:10s}: mean={col.mean():+.7f}  std={col.std():.6f}  min={col.min():+.6f}  max={col.max():+.6f}")
