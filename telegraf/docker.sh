#!/bin/sh

set -eux

# Push via internal harbor-core (Cloudflare 413s large uploads); pods pull the same image as harbor.gladiators.dev.
# Both arches: hungary runs amd64 (xpand, jonapot) and arm64 nodes.
TAG=${TAG:-1.39.3-slim}
time docker buildx build --platform linux/amd64,linux/arm64 --push \
  --progress=plain \
  --builder k8s-buildkit \
  --output type=image,push=true,oci-mediatypes=true,compression=estargz,force-compression=true \
  --cache-to type=registry,ref=harbor-core.db.svc.cluster.local/library/telegraf:buildcache,mode=min \
  --cache-from type=registry,ref=harbor-core.db.svc.cluster.local/library/telegraf:buildcache \
  -t harbor-core.db.svc.cluster.local/library/telegraf:"$TAG" .
