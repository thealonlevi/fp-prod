package main

import (
	"context"
	"flag"
	"log"
	"net"
	"time"

	"github.com/negasus/haproxy-spoe-go/action"
	"github.com/negasus/haproxy-spoe-go/agent"
	"github.com/negasus/haproxy-spoe-go/logger"
	"github.com/negasus/haproxy-spoe-go/request"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

/* ───── CLI flags ───────────────────────────────────────────────────────── */

var (
	listenAddr   = flag.String("listen", ":9000", "SPOE listen address")
	redisAddr    = flag.String("redis", "127.0.0.1:6379", "Redis host:port")
	redisPass    = flag.String("redis-password", "", "Redis AUTH password")
	redisDB      = flag.Int("redis-db", 0, "Redis DB number")
	timeoutRedis = flag.Duration("redis-timeout", 500*time.Millisecond, "Redis dial/read timeout")
)

var (
	ctx = context.Background()
	rdb *redis.Client
)

/* ───── SPOE message handler ───────────────────────────────────────────── */

func authHandler(req *request.Request) {
	msg, err := req.Messages.GetByName("check_credentials")
	if err != nil {
		req.Actions.SetVar(action.ScopeTransaction, "auth_ok", 0)
		return
	}

	usr, ok1 := msg.KV.Get("username")
	pwd, ok2 := msg.KV.Get("password")
	if !ok1 || !ok2 {
		req.Actions.SetVar(action.ScopeTransaction, "auth_ok", 0)
		return
	}

	username := usr.(string)
	password := pwd.(string)

	hash, err := rdb.HGet(ctx, "user:"+username, "pwd").Result()
	if err != nil {
		req.Actions.SetVar(action.ScopeTransaction, "auth_ok", 0)
		return
	}

	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil {
		req.Actions.SetVar(action.ScopeTransaction, "auth_ok", 1)
	} else {
		req.Actions.SetVar(action.ScopeTransaction, "auth_ok", 0)
	}
}

/* ───── main ───────────────────────────────────────────────────────────── */

func main() {
	flag.Parse()

	/* Redis connection */
	rdb = redis.NewClient(&redis.Options{
		Addr:        *redisAddr,
		Password:    *redisPass,
		DB:          *redisDB,
		DialTimeout: *timeoutRedis,
		ReadTimeout: *timeoutRedis,
	})
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatalf("Redis ping failed: %v", err)
	}

	/* TCP listener */
	listener, err := net.Listen("tcp", *listenAddr)
	if err != nil {
		log.Fatalf("listen error: %v", err)
	}

	/* SPOE agent */
	spoeAgent := agent.New(authHandler, logger.NewDefaultLog())
	log.Printf("spoe-auth-agent listening on %s", *listenAddr)

	if err := spoeAgent.Serve(listener); err != nil {
		log.Fatalf("agent serve error: %v", err)
	}
}
