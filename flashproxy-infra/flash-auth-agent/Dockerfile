# ───── build stage ─────
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o /spoa .

# ───── runtime stage ─────
FROM alpine:3.20
RUN addgroup -S spoa && adduser -S spoa -G spoa
USER spoa

COPY --from=build /spoa /spoa
EXPOSE 9000/tcp
ENTRYPOINT ["/spoa"]
# default flags can be overridden from docker-compose
CMD ["-listen=:9000","-redis=redis:6379"]
