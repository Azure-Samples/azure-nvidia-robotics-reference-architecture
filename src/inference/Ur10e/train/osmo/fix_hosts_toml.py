import os

d = '/etc/containerd/certs.d/192.168.1.100:5000'
os.makedirs(d, exist_ok=True)

content = '''server = "http://192.168.1.100:5000"

[host."http://192.168.1.100:5000"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
'''

with open(d + '/hosts.toml', 'w') as f:
    f.write(content)

print('Written hosts.toml:')
with open(d + '/hosts.toml') as f:
    print(f.read())
