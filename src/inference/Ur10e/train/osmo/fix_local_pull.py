import subprocess, time

p = "/etc/containerd/config.toml"
with open(p) as f:
    c = f.read()

c = c.replace("use_local_image_pull = false", "use_local_image_pull = true")

with open(p, "w") as f:
    f.write(c)

print("Set use_local_image_pull = true")

# Restart containerd
subprocess.run(["systemctl", "restart", "containerd"], check=True)
print("Restarted containerd")
time.sleep(5)

# Verify
result = subprocess.run(["bash", "-c", "containerd config dump 2>&1 | grep use_local"],
                       capture_output=True, text=True)
print(f"Config: {result.stdout.strip()}")

# Test pull
print("Testing crictl pull...")
result = subprocess.run(["crictl", "pull", "192.168.1.100:5000/ur10e-act-train:latest"],
                       capture_output=True, text=True, timeout=300)
print(f"Exit: {result.returncode}")
print(f"Out: {result.stdout}")
if result.stderr:
    print(f"Err: {result.stderr}")
