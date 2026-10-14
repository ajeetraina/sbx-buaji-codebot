# Sandbox template image for BuaJi.
#
# Build once and push to your registry, then store the image name in the
# BUAJI_TEMPLATE CI variable. Baking BuaJi's dependencies in means the sandbox
# never has to download anything at review time, so it needs no internet access
# of its own.
#
#   docker buildx build -f buaji.sandbox.Dockerfile -t <registry>/buaji:latest --push .
FROM docker/sandbox-templates:shell
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-requests git \
 && rm -rf /var/lib/apt/lists/*
USER agent
