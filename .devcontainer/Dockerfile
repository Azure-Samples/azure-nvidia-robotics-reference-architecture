FROM mcr.microsoft.com/devcontainers/python:3.11-bookworm

RUN rm -f \
	/etc/apt/sources.list.d/yarn.list \
	/usr/share/keyrings/yarnkey.gpg \
	/etc/apt/keyrings/yarn.gpg \
	/etc/apt/trusted.gpg.d/yarn.gpg

RUN curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg \
	| gpg --dearmor \
	| tee /usr/share/keyrings/yarnkey.gpg > /dev/null \
	&& echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" \
	| tee /etc/apt/sources.list.d/yarn.list \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends yarn \
	&& rm -rf /var/lib/apt/lists/*
