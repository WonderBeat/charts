# Slim telegraf: only the plugins telegraf.conf uses. Stock binary is 301MiB and thrashed page cache under the
# 148Mi memcg limit (refault storm -> iowait -> load ~5). Keep the tag list in sync with the config.
ARG TELEGRAF_VERSION=1.39.3

FROM --platform=$BUILDPLATFORM golang:1-alpine AS build
ARG TELEGRAF_VERSION TARGETOS TARGETARCH
RUN apk add --no-cache git
RUN git clone --depth 1 --branch v${TELEGRAF_VERSION} https://github.com/influxdata/telegraf /src
WORKDIR /src
RUN --mount=type=cache,target=/root/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
  CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath \
  -tags "custom,inputs.cpu,inputs.disk,inputs.mem,inputs.system,inputs.net,inputs.tail,inputs.prometheus,\
inputs.internal,inputs.ping,outputs.influxdb,outputs.loki,processors.starlark,parsers.grok,serializers.influx" \
  -ldflags "-s -w -X github.com/influxdata/telegraf/internal.Version=${TELEGRAF_VERSION}" \
  -o /telegraf ./cmd/telegraf

FROM alpine:3
# iputils: inputs.ping uses method=exec; tzdata: grok_timezone=Local
RUN apk add --no-cache ca-certificates tzdata iputils
COPY --from=build /telegraf /usr/bin/telegraf
ENTRYPOINT ["/usr/bin/telegraf"]
