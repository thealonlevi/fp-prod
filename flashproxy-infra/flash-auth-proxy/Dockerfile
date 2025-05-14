# ───── build stage ─────
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o /auth-proxy .

# ───── runtime stage ─────
FROM alpine:3.20
RUN adduser -S proxy
USER proxy

COPY --from=build /auth-proxy /auth-proxy
EXPOSE 443/tcp 9100/tcp
ENTRYPOINT ["/auth-proxy"]
CMD ["-listen=:443","-backend=127.0.0.1:8443","-redis=127.0.0.1:6379"]
