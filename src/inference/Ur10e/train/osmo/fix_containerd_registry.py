import os, subprocess, time

config_path = '/etc/containerd/config.toml'

# Read current config
with open(config_path, 'r') as f:
    content = f.read()

# Find the transfer.v1.local section and update its config_path
marker = '[plugins."io.containerd.transfer.v1.local"]'
parts = content.split(marker)
if len(parts) == 2:
    after = parts[1].replace('config_path = ""', 
        'config_path = "/etc/containerd/certs.d:/etc/docker/certs.d"', 1)
    new_content = parts[0] + marker + after
    
    # Backup and write
    with open(config_path + '.bak2', 'w') as f:
        f.write(content)
    with open(config_path, 'w') as f:
        f.write(new_content)
    print('Updated transfer plugin config_path in config.toml')
else:
    print(f'ERROR: Could not find transfer section (split={len(parts)} parts)')

# Verify
with open(config_path, 'r') as f:
    new = f.read()
for line in new.splitlines():
    if 'config_path' in line and 'plugin_config' not in line:
        print(f'  config_path line: {line.strip()}')

# Ensure hosts.toml exists with correct content
d = '/etc/containerd/certs.d/192.168.1.100:5000'
os.makedirs(d, exist_ok=True)
hosts_content = 'server = "http://192.168.1.100:5000"\n\n[host."http://192.168.1.100:5000"]\n  capabilities = ["pull", "resolve", "push"]\n  skip_verify = true\n'
with open(os.path.join(d, 'hosts.toml'), 'w') as f:
    f.write(hosts_content)
print('Written certs.d hosts.toml')

# Restart containerd
result = subprocess.run(['systemctl', 'restart', 'containerd'], 
                       capture_output=True, text=True)
print(f'Restart exit code: {result.returncode}')
if result.stderr:
    print(f'Restart stderr: {result.stderr}')

# Wait for containerd to stabilize
time.sleep(5)

# Verify - check transfer plugin in config dump
result = subprocess.run(['bash', '-c', 'containerd config dump 2>&1 | grep -B2 -A5 "transfer.v1.local"'],
                       capture_output=True, text=True)
print(f'Transfer plugin config dump:\n{result.stdout}')

# Test pull with crictl
print('Testing crictl pull...')
result = subprocess.run(['crictl', 'pull', '192.168.1.100:5000/ur10e-act-train:latest'],
                       capture_output=True, text=True, timeout=300)
print(f'Pull exit code: {result.returncode}')
print(f'Pull stdout: {result.stdout}')
if result.stderr:
    print(f'Pull stderr: {result.stderr}')
