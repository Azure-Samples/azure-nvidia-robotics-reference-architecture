"""Quick verification script for batch converter output."""
import pathlib
import pyarrow.parquet as pq

p = pathlib.Path("C:/Data/houston-lerobot-test2")

print("=== Files ===")
for f in sorted(p.rglob("*")):
    if f.is_file():
        print(f.relative_to(p))
print()

print("=== Episode Metadata ===")
t = pq.read_table(str(p / "meta/episodes/chunk-000/file-000.parquet"))
print(t.to_pandas().to_string())
print()

print("=== Chunk-000 Data (Episode 0) ===")
t0 = pq.read_table(str(p / "data/chunk-000/file-000.parquet"))
df0 = t0.to_pandas()
print(f"Rows: {len(df0)}")
print(f"Global index: {df0['index'].iloc[0]} - {df0['index'].iloc[-1]}")
print(f"frame_index: {df0['frame_index'].iloc[0]} - {df0['frame_index'].iloc[-1]}")
print()

print("=== Chunk-001 Data (Episode 1) ===")
t1 = pq.read_table(str(p / "data/chunk-001/file-001.parquet"))
df1 = t1.to_pandas()
print(f"Rows: {len(df1)}")
print(f"Global index: {df1['index'].iloc[0]} - {df1['index'].iloc[-1]}")
print(f"frame_index: {df1['frame_index'].iloc[0]} - {df1['frame_index'].iloc[-1]}")
