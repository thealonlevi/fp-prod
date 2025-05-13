module github.com/thealonlevi/fp-prod/flashproxy-infra/flash-auth-agent

go 1.22

require (
	github.com/negasus/haproxy-spoe-go v1.0.6 // <─ root module at v1.0.6
	github.com/redis/go-redis/v9 v9.5.0
	golang.org/x/crypto v0.18.0
)

require (
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
)
