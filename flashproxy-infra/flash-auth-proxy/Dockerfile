###############################################################################
#  Build stage  – compile the Go binary statically
###############################################################################
FROM golang:1.22-alpine AS build
WORKDIR /src

# deps
COPY go.mod go.sum ./
RUN go mod download

# source
COPY . .
RUN CGO_ENABLED=0 go build -o /auth-proxy .

###############################################################################
#  Runtime stage – smallest possible image, non-root, can bind :443
###############################################################################
FROM alpine:3.20

# setcap comes from libcap
RUN apk add --no-cache libcap

# copy the binary and grant the low-port capability
COPY --from=build /auth-proxy /usr/local/bin/auth-proxy
RUN setcap 'cap_net_bind_service=+ep' /usr/local/bin/auth-proxy

# create unprivileged user and drop to it
RUN adduser -S -D proxy
USER proxy

EXPOSE 443/tcp 9100/tcp
ENTRYPOINT ["/usr/local/bin/auth-proxy"]
CMD ["-listen=:443","-backend=127.0.0.1:8443","-redis=127.0.0.1:6379"]
